import Foundation

/// Serializes menu bar operations and applies retries, verification and rollback.
///
/// Only one move may run at a time: synthesized drags fight over the same
/// pointer and overlapping operations produce corrupted layouts. The
/// coordinator is an actor so callers can await operations without extra locks.
public actor LayoutCoordinator {
    public struct Configuration: Sendable {
        public var maxAttempts: Int
        public var attemptDelayMs: Int
        public var verificationSamples: Int
        public var verificationIntervalMs: Int
        public var verificationTolerance: Double
        public var abortBatchAfterFailures: Int

        public init(
            maxAttempts: Int = 5,
            attemptDelayMs: Int = 120,
            verificationSamples: Int = 10,
            verificationIntervalMs: Int = 50,
            verificationTolerance: Double = 8,
            abortBatchAfterFailures: Int = 2
        ) {
            self.maxAttempts = maxAttempts
            self.attemptDelayMs = attemptDelayMs
            self.verificationSamples = verificationSamples
            self.verificationIntervalMs = verificationIntervalMs
            self.verificationTolerance = verificationTolerance
            self.abortBatchAfterFailures = abortBatchAfterFailures
        }

        public static let `default` = Configuration()
    }

    public struct Outcome: Sendable, Equatable {
        public var itemID: String
        public var itemName: String
        public var fromSection: MenuBarSection
        public var toSection: MenuBarSection
        public var result: OperationLog.Result
        public var error: MacBarError?
        public var attempts: Int
        public var finalFrame: ItemFrame?

        public var isSuccess: Bool { result == .success }
        public var isFailure: Bool { result == .failed }
    }

    public struct BatchOutcome: Sendable, Equatable {
        public var outcomes: [Outcome]
        public var aborted: Bool

        public var successCount: Int { outcomes.filter(\.isSuccess).count }
        public var skippedCount: Int { outcomes.filter { $0.result == .skipped }.count }
        public var failureCount: Int { outcomes.filter(\.isFailure).count }
        public var isEmpty: Bool { outcomes.isEmpty }

        public static let empty = BatchOutcome(outcomes: [], aborted: false)
    }

    private let scanner: MenuBarScanning
    private let mover: MenuBarMoving
    private let permissions: PermissionProviding
    private let store: LayoutStoring
    private let clock: ClockProviding
    private let engine: LayoutEngine
    private let conflictDetector: ConflictDetecting
    private let configuration: Configuration
    private var runningTasks = 0

    public init(
        scanner: MenuBarScanning,
        mover: MenuBarMoving,
        permissions: PermissionProviding,
        store: LayoutStoring,
        clock: ClockProviding = SystemClock(),
        engine: LayoutEngine = LayoutEngine(),
        conflictDetector: ConflictDetecting = NoConflictDetector(),
        configuration: Configuration = .default
    ) {
        self.scanner = scanner
        self.mover = mover
        self.permissions = permissions
        self.store = store
        self.clock = clock
        self.engine = engine
        self.conflictDetector = conflictDetector
        self.configuration = configuration
    }

    public var isBusy: Bool { runningTasks > 0 }

    /// Pre-flight checks shared by single and batch operations.
    public func preflight(policy: ConflictPolicy = .warn) throws {
        guard permissions.status(of: .accessibility).isGranted else {
            throw MacBarError.accessibilityDenied
        }
        guard mover.isEventPostingAvailable() else {
            throw MacBarError.eventCreationFailed
        }
        let conflicts = conflictDetector.runningManagers()
        if !conflicts.isEmpty {
            MacBarLog.warning(.conflict, "menu bar manager conflict detected count=\(conflicts.count)")
            if policy == .block {
                throw MacBarError.conflictDetected(apps: conflicts)
            }
        }
    }

    /// Builds and sanitizes a plan for the current items.
    public func plan(
        items: [MenuBarItemRecord],
        targetSections: [String: MenuBarSection],
        anchors: LayoutAnchors,
        display: DisplayGeometry,
        includeAlreadyPlaced: Bool = false
    ) -> LayoutPlan {
        let raw = engine.plan(
            items: items,
            targetSections: targetSections,
            anchors: anchors,
            display: display,
            includeAlreadyPlaced: includeAlreadyPlaced
        )
        return engine.sanitize(raw, display: display)
    }

    /// Moves one item into the requested section.
    @discardableResult
    public func move(
        item: MenuBarItemRecord,
        to section: MenuBarSection,
        anchors: LayoutAnchors,
        display: DisplayGeometry,
        logType: OperationLog.OpType = .move
    ) async throws -> Outcome {
        try preflight()
        let target = engine.targetFrame(for: section, index: 0, size: item.frame, anchors: anchors, display: display)
        if engine.isAt(item: item, section: section, anchors: anchors) {
            let log = makeLog(
                type: logType, item: item, from: item.section, to: section,
                fromFrame: item.frame, toFrame: item.frame, result: .skipped,
                attempts: 0, startedAt: clock.now()
            )
            store.appendLog(log)
            return outcome(item: item, to: section, result: .skipped, error: nil, attempts: 0, frame: item.frame)
        }
        guard item.isMovable else {
            throw MacBarError.itemNotMovable(itemID: item.id)
        }
        if section != .visible && !item.isHideable {
            throw MacBarError.itemNotMovable(itemID: item.id)
        }
        return await performMove(item: item, to: section, target: target, logType: logType)
    }

    /// Applies every move in the plan, aborting early on fatal errors or when too
    /// many consecutive moves fail.
    public func apply(
        plan: LayoutPlan,
        items: [MenuBarItemRecord],
        anchors: LayoutAnchors,
        display: DisplayGeometry,
        logType: OperationLog.OpType = .move,
        progress: (@Sendable @MainActor (Outcome) -> Void)? = nil
    ) async -> BatchOutcome {
        if plan.moves.isEmpty {
            return .empty
        }
        do {
            try preflight()
        } catch {
            let typed = (error as? MacBarError) ?? .unknown(error.localizedDescription)
            return BatchOutcome(
                outcomes: plan.moves.map {
                    Outcome(
                        itemID: $0.itemID, itemName: $0.itemID, fromSection: $0.from, toSection: $0.to,
                        result: .failed, error: typed, attempts: 0, finalFrame: nil
                    )
                },
                aborted: true
            )
        }

        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        var outcomes: [Outcome] = []
        var consecutiveFailures = 0
        var aborted = false

        for move in plan.moves {
            if Task.isCancelled {
                aborted = true
                break
            }
            guard let item = byID[move.itemID] else {
                outcomes.append(
                    Outcome(
                        itemID: move.itemID, itemName: move.itemID, fromSection: move.from, toSection: move.to,
                        result: .failed, error: .itemDisappeared(itemID: move.itemID), attempts: 0, finalFrame: nil
                    )
                )
                consecutiveFailures += 1
                if consecutiveFailures >= configuration.abortBatchAfterFailures {
                    aborted = true
                    break
                }
                continue
            }
            let result = await performMove(item: item, to: move.to, target: move.targetFrame, logType: logType)
            outcomes.append(result)
            if let progress {
                await progress(result)
            }
            if result.isSuccess || result.result == .skipped {
                consecutiveFailures = 0
            } else {
                consecutiveFailures += 1
                if result.error?.isFatalForBatch == true {
                    aborted = true
                    break
                }
            }
            if consecutiveFailures >= configuration.abortBatchAfterFailures {
                MacBarLog.warning(.layout, "batch aborted after consecutive failures=\(consecutiveFailures)")
                aborted = true
                break
            }
        }
        return BatchOutcome(outcomes: outcomes, aborted: aborted)
    }

    /// Moves the item back to its recorded original frame.
    public func restore(item: MenuBarItemRecord, originalFrame: ItemFrame) async -> Outcome {
        let startedAt = clock.now()
        guard item.isMovable, permissions.status(of: .accessibility).isGranted else {
            let log = makeLog(
                type: .restore, item: item, from: item.section, to: .visible,
                fromFrame: item.frame, toFrame: nil, result: .failed, attempts: 0,
                startedAt: startedAt, error: .accessibilityDenied
            )
            store.appendLog(log)
            return outcome(item: item, to: .visible, result: .failed, error: .accessibilityDenied, attempts: 0, frame: nil)
        }
        try? await mover.drag(
            itemID: item.id, windowID: item.windowID, ownerPID: item.ownerPID,
            from: item.frame.center, to: originalFrame.center
        )
        let verified = await verify(itemID: item.id, expected: originalFrame)
        let result: OperationLog.Result = verified != nil ? .success : .failed
        store.appendLog(
            makeLog(
                type: .restore, item: item, from: item.section, to: .visible,
                fromFrame: item.frame, toFrame: verified, result: result,
                attempts: 1, startedAt: startedAt,
                error: verified == nil ? .moveTimedOut(itemID: item.id) : nil
            )
        )
        return outcome(
            item: item, to: .visible, result: result,
            error: verified == nil ? .moveTimedOut(itemID: item.id) : nil,
            attempts: 1, frame: verified
        )
    }

    // MARK: - Internals

    private func performMove(
        item: MenuBarItemRecord,
        to section: MenuBarSection,
        target: ItemFrame,
        logType: OperationLog.OpType
    ) async -> Outcome {
        runningTasks += 1
        defer { runningTasks -= 1 }

        let startedAt = clock.now()
        let original = item.frame
        var machine = MoveMachine()
        machine.apply(.start)
        var lastError: MacBarError = .moveTimedOut(itemID: item.id)
        var attemptsUsed = 0

        for attempt in 1...configuration.maxAttempts {
            if Task.isCancelled {
                lastError = .cancelled
                break
            }
            attemptsUsed = attempt
            do {
                try await mover.drag(
                    itemID: item.id, windowID: item.windowID, ownerPID: item.ownerPID,
                    from: original.center, to: target.center
                )
                if let verified = await verify(itemID: item.id, expected: target) {
                    machine.apply(.success)
                    store.appendLog(
                        makeLog(
                            type: logType, item: item, from: item.section, to: section,
                            fromFrame: original, toFrame: verified, result: .success,
                            attempts: attempt, startedAt: startedAt
                        )
                    )
                    appendMovedSnapshot(itemID: item.id, from: item.section, to: section, frame: verified)
                    return outcome(item: item, to: section, result: .success, error: nil, attempts: attempt, frame: verified)
                }
                lastError = .layoutVerificationFailed(itemID: item.id)
            } catch is CancellationError {
                lastError = .cancelled
                break
            } catch let error as MacBarError {
                lastError = error
                if error.isFatalForBatch { break }
            } catch {
                lastError = .unknown(error.localizedDescription)
            }
            machine.apply(.failure)
            machine.apply(.retry)
            MacBarLog.warning(
                .layout,
                "move attempt failed item=\(MacBarLog.sanitize(item.id)) attempt=\(attempt) code=\(lastError.code)"
            )
            try? await clock.sleep(milliseconds: configuration.attemptDelayMs)
            if let refreshed = await scanner.frames(for: [item.id])[item.id],
               refreshed.isApproximatelyEqual(to: target, tolerance: configuration.verificationTolerance) {
                machine.apply(.success)
                return outcome(item: item, to: section, result: .success, error: nil, attempts: attempt, frame: refreshed)
            }
            try? await mover.wakeUp(
                itemID: item.id, windowID: item.windowID, ownerPID: item.ownerPID,
                at: (await scanner.frames(for: [item.id])[item.id] ?? original).center
            )
        }

        // Roll back so a partially applied layout never remains on screen.
        if lastError != .cancelled {
            let currentFrame = await scanner.frames(for: [item.id])[item.id] ?? original
            try? await mover.drag(
                itemID: item.id, windowID: item.windowID, ownerPID: item.ownerPID,
                from: currentFrame.center, to: original.center
            )
        }
        machine.apply(.rollback)
        store.appendLog(
            makeLog(
                type: logType, item: item, from: item.section, to: section,
                fromFrame: original, toFrame: nil, result: .failed,
                attempts: attemptsUsed, startedAt: startedAt, error: lastError
            )
        )
        return outcome(item: item, to: section, result: .failed, error: lastError, attempts: attemptsUsed, frame: nil)
    }

    /// Polls the window server until the item lands near the expected frame.
    private func verify(itemID: String, expected: ItemFrame) async -> ItemFrame? {
        for _ in 0..<configuration.verificationSamples {
            try? await Task.sleep(nanoseconds: UInt64(configuration.verificationIntervalMs) * 1_000_000)
            guard let frame = await scanner.frames(for: [itemID])[itemID] else { continue }
            if frame.isApproximatelyEqual(to: expected, tolerance: configuration.verificationTolerance) {
                return frame
            }
        }
        return nil
    }

    private func appendMovedSnapshot(itemID: String, from: MenuBarSection, to: MenuBarSection, frame: ItemFrame) {
        guard let snapshot = try? store.loadSnapshot() else { return }
        var updated = snapshot
        updated.move(itemID: itemID, to: to)
        updated.originalFrames[itemID] = frame
        updated.updatedAt = clock.now()
        try? store.saveSnapshot(updated)
    }

    private func outcome(
        item: MenuBarItemRecord,
        to section: MenuBarSection,
        result: OperationLog.Result,
        error: MacBarError?,
        attempts: Int,
        frame: ItemFrame?
    ) -> Outcome {
        Outcome(
            itemID: item.id,
            itemName: item.displayName,
            fromSection: item.section,
            toSection: section,
            result: result,
            error: error,
            attempts: attempts,
            finalFrame: frame
        )
    }

    private func makeLog(
        type: OperationLog.OpType,
        item: MenuBarItemRecord,
        from: MenuBarSection,
        to: MenuBarSection,
        fromFrame: ItemFrame?,
        toFrame: ItemFrame?,
        result: OperationLog.Result,
        attempts: Int,
        startedAt: Date,
        error: MacBarError? = nil
    ) -> OperationLog {
        OperationLog(
            opType: type,
            itemID: item.id,
            itemName: item.displayName,
            fromSection: from,
            toSection: to,
            fromFrame: fromFrame,
            toFrame: toFrame,
            result: result,
            errorCode: error?.code,
            message: error?.localizedDescription,
            retryCount: attempts,
            durationMs: Int(clock.now().timeIntervalSince(startedAt) * 1000),
            startedAt: startedAt,
            finishedAt: clock.now(),
            appVersion: MacBarVersion.current
        )
    }
}

/// Default conflict detector used when no system implementation is supplied.
public struct NoConflictDetector: ConflictDetecting {
    public init() {}
    public func runningManagers() -> [String] { [] }
}
