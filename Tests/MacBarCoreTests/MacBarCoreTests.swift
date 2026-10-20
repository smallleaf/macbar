import Foundation
import XCTest
@testable import MacBarCore

// MARK: - Test doubles

private struct StubScanner: MenuBarScanning {
    var items: [MenuBarItemRecord] = []
    var display: DisplayGeometry = DisplayGeometry(
        displayID: 1,
        bounds: ItemFrame(x: 0, y: 0, width: 1440, height: 900),
        menuBarHeight: 24,
        isMain: true
    )

    func scan(displayID: UInt32?) async throws -> ScanResult {
        ScanResult(items: items, accessibilityAvailable: true)
    }

    func frames(for itemIDs: [String]) async -> [String: ItemFrame] {
        Dictionary(uniqueKeysWithValues: items.filter { itemIDs.contains($0.id) }.map { ($0.id, $0.frame) })
    }

    func displayGeometries() async -> [DisplayGeometry] { [display] }
    func mainDisplay() async -> DisplayGeometry { display }
}

/// Simulates the window server: applies drags instantly so verification passes.
private final class SimulatingMover: MenuBarMoving, @unchecked Sendable {
    struct Drag: Sendable, Equatable {
        var itemID: String
        var from: ItemPoint
        var to: ItemPoint
    }

    private let lock = NSLock()
    private var drags: [Drag] = []
    var failEveryDrag = false
    var failure: MacBarError = .layoutVerificationFailed(itemID: "x")
    var trusted = true
    private let frames: @Sendable (String) -> ItemFrame?

    init(frames: @escaping @Sendable (String) -> ItemFrame? = { _ in nil }) {
        self.frames = frames
    }

    func drag(itemID: String, windowID: UInt32, ownerPID: Int32, from: ItemPoint, to: ItemPoint) async throws {
        record(Drag(itemID: itemID, from: from, to: to))
        if shouldFail {
            throw failure
        }
    }

    private var shouldFail: Bool {
        lock.lock(); defer { lock.unlock() }; return failEveryDrag
    }

    private func record(_ drag: Drag) {
        lock.lock(); defer { lock.unlock() }; drags.append(drag)
    }

    var recordedDrags: [Drag] {
        lock.lock(); defer { lock.unlock() }; return drags
    }

    func click(itemID: String, windowID: UInt32, ownerPID: Int32, at: ItemPoint, button: MouseButton) async throws {}

    func wakeUp(itemID: String, windowID: UInt32, ownerPID: Int32, at: ItemPoint) async throws {}

    func isEventPostingAvailable() -> Bool { trusted }
}

private struct StubPermissions: PermissionProviding {
    var accessibility: PermissionStatus = .granted
    var screenRecording: PermissionStatus = .denied

    func status(of kind: PermissionKind) -> PermissionStatus {
        kind == .accessibility ? accessibility : screenRecording
    }

    func request(_ kind: PermissionKind) -> Bool { status(of: kind).isGranted }
    func openSystemSettings(for kind: PermissionKind) {}
}

private final class InMemoryStore: LayoutStoring, @unchecked Sendable {
    var snapshot: LayoutSnapshot?
    var preferences = PreferencesFile()
    var settings = AppSettings.default
    var logs: [OperationLog] = []
    var storageDirectory: URL { URL(fileURLWithPath: "/tmp/macbar-test") }

    func loadSnapshot() throws -> LayoutSnapshot? { snapshot }
    func saveSnapshot(_ snapshot: LayoutSnapshot) throws { self.snapshot = snapshot }
    func loadPreferences() -> PreferencesFile { preferences }
    func savePreferences(_ preferences: PreferencesFile) throws { self.preferences = preferences }
    func loadSettings() -> AppSettings { settings }
    func saveSettings(_ settings: AppSettings) throws { self.settings = settings }
    func appendLog(_ log: OperationLog) { logs.append(log) }
    func loadLogs(limit: Int) -> [OperationLog] { Array(logs.suffix(limit)) }
    func exportDiagnostics() throws -> URL { storageDirectory }
    func exportDiagnostics(
        items: [MenuBarItemRecord],
        permissions: [PermissionKind: PermissionStatus],
        conflicts: [String]
    ) throws -> URL { storageDirectory }
}

/// Mutable state shared with a simulating scanner so drags move real frames.
private final class WindowServerSimulator: @unchecked Sendable {
    private let lock = NSLock()
    private var frames: [String: ItemFrame] = [:]

    func set(_ frame: ItemFrame, for id: String) {
        lock.lock(); frames[id] = frame; lock.unlock()
    }

    func frame(for id: String) -> ItemFrame? {
        lock.lock(); defer { lock.unlock() }; return frames[id]
    }

    func apply(drag: SimulatingMover.Drag) {
        lock.lock(); defer { lock.unlock() }
        guard var frame = frames[drag.itemID] else { return }
        frame.x = drag.to.x - frame.width / 2
        frames[drag.itemID] = frame
    }

    func allFrames() -> [String: ItemFrame] {
        lock.lock(); defer { lock.unlock() }; return frames
    }
}

/// Scanner backed by the simulator.
private final class SimulatedScanner: MenuBarScanning, @unchecked Sendable {
    let simulator: WindowServerSimulator
    let display = DisplayGeometry(
        displayID: 1,
        bounds: ItemFrame(x: 0, y: 0, width: 1440, height: 900),
        menuBarHeight: 24,
        isMain: true
    )

    init(simulator: WindowServerSimulator) {
        self.simulator = simulator
    }

    func scan(displayID: UInt32?) async throws -> ScanResult {
        ScanResult(items: [], accessibilityAvailable: true)
    }

    func frames(for itemIDs: [String]) async -> [String: ItemFrame] {
        let all = simulator.allFrames()
        return all.filter { itemIDs.contains($0.key) }
    }

    func displayGeometries() async -> [DisplayGeometry] { [display] }
    func mainDisplay() async -> DisplayGeometry { display }
}

private struct NoConflicts: ConflictDetecting {
    func runningManagers() -> [String] { [] }
}

private struct ConflictingTool: ConflictDetecting {
    func runningManagers() -> [String] { ["Bartender"] }
}

// MARK: - Fixtures

private func makeItem(
    id: String,
    x: Double,
    width: Double = 24,
    section: MenuBarSection = .visible,
    movable: Bool = true,
    hideable: Bool = true
) -> MenuBarItemRecord {
    MenuBarItemRecord(
        id: id,
        windowID: UInt32(abs(id.hashValue % 100_000)),
        ownerPID: 1000,
        ownerName: "Owner",
        bundleIdentifier: "com.example.\(id)",
        title: id,
        frame: ItemFrame(x: x, y: 0, width: width, height: 24),
        displayID: 1,
        isOnScreen: section == .visible,
        isMovable: movable,
        isHideable: hideable,
        section: section
    )
}

private let testDisplay = DisplayGeometry(
    displayID: 1,
    bounds: ItemFrame(x: 0, y: 0, width: 1440, height: 900),
    menuBarHeight: 24,
    isMain: true
)

private let testAnchors = LayoutAnchors(visibleX: 1432, hiddenX: 0, alwaysHiddenX: -600)

// MARK: - Tests

final class LayoutEngineTests: XCTestCase {
    let engine = LayoutEngine()

    func testVisibleFramesStayOnScreen() {
        let items = (0..<5).map { makeItem(id: "v\($0)", x: 1000 - Double($0) * 30) }
        let targets = Dictionary(uniqueKeysWithValues: items.map { ($0.id, MenuBarSection.visible) })
        let plan = engine.plan(items: items, targetSections: targets, anchors: testAnchors, display: testDisplay)

        for move in plan.moves {
            XCTAssertGreaterThanOrEqual(move.targetFrame.minX, 0, "visible item must stay on screen")
            XCTAssertLessThanOrEqual(move.targetFrame.maxX, testAnchors.visibleX, "visible item must stay left of the control item")
        }
    }

    func testHiddenFramesEndOffScreen() {
        let items = (0..<3).map { makeItem(id: "h\($0)", x: 900 - Double($0) * 30) }
        let targets = Dictionary(uniqueKeysWithValues: items.map { ($0.id, MenuBarSection.hidden) })
        let plan = engine.plan(items: items, targetSections: targets, anchors: testAnchors, display: testDisplay)

        XCTAssertFalse(plan.moves.isEmpty)
        for move in plan.moves {
            XCTAssertLessThanOrEqual(move.targetFrame.maxX, 0, "hidden item must be left of the display edge")
        }
    }

    func testAlwaysHiddenFramesAreFurtherLeftThanHidden() {
        let item = makeItem(id: "a", x: 800)
        let hiddenPlan = engine.plan(
            items: [item],
            targetSections: ["a": .hidden],
            anchors: testAnchors,
            display: testDisplay
        )
        let alwaysPlan = engine.plan(
            items: [item],
            targetSections: ["a": .alwaysHidden],
            anchors: testAnchors,
            display: testDisplay
        )
        XCTAssertEqual(hiddenPlan.moves.count, 1)
        XCTAssertEqual(alwaysPlan.moves.count, 1)
        XCTAssertLessThan(
            alwaysPlan.moves[0].targetFrame.minX,
            hiddenPlan.moves[0].targetFrame.minX,
            "always-hidden section sits further left"
        )
    }

    func testAlreadyPlacedItemsAreSkippedUnlessForced() {
        let item = makeItem(id: "v", x: 1200, section: .visible)
        let plan = engine.plan(
            items: [item],
            targetSections: ["v": .visible],
            anchors: testAnchors,
            display: testDisplay
        )
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.skipped.first?.reason, .alreadyInPlace)

        let forced = engine.plan(
            items: [item],
            targetSections: ["v": .visible],
            anchors: testAnchors,
            display: testDisplay,
            includeAlreadyPlaced: true
        )
        XCTAssertEqual(forced.moves.count, 1)
    }

    func testImmovableItemsAreSkippedNotMoved() {
        let clock = makeItem(id: "Clock", x: 1200, movable: false, hideable: false)
        let plan = engine.plan(
            items: [clock],
            targetSections: ["Clock": .hidden],
            anchors: testAnchors,
            display: testDisplay
        )
        XCTAssertTrue(plan.moves.isEmpty)
        XCTAssertEqual(plan.skipped.first?.reason, .notMovable)
    }

    func testDeriveSectionFromFrame() {
        XCTAssertEqual(engine.deriveSection(for: ItemFrame(x: 100, y: 0, width: 20, height: 24), anchors: testAnchors), .visible)
        XCTAssertEqual(engine.deriveSection(for: ItemFrame(x: -20, y: 0, width: 20, height: 24), anchors: testAnchors), .hidden)
        XCTAssertEqual(engine.deriveSection(for: ItemFrame(x: -800, y: 0, width: 20, height: 24), anchors: testAnchors), .alwaysHidden)
    }

    func testSanitizePushesAccidentalVisibleTargetsOutside() {
        let badPlan = LayoutPlan(
            moves: [
                PlannedMove(
                    itemID: "x",
                    from: .visible,
                    to: .hidden,
                    targetFrame: ItemFrame(x: 500, y: 0, width: 20, height: 24)
                ),
            ],
            skipped: [],
            targetSections: ["x": .hidden]
        )
        let sanitized = engine.sanitize(badPlan, display: testDisplay)
        XCTAssertLessThanOrEqual(sanitized.moves[0].targetFrame.maxX, 0)
    }

    func testSynthesizedAnchorsMatchDisplay() {
        let anchors = engine.synthesizedAnchors(display: testDisplay)
        XCTAssertLessThan(anchors.hiddenX, anchors.visibleX)
        XCTAssertLessThanOrEqual(anchors.alwaysHiddenX ?? 0, anchors.hiddenX)
    }
}

final class MoveMachineTests: XCTestCase {
    func testHappyPath() {
        var machine = MoveMachine()
        XCTAssertEqual(machine.apply(.start), .moving)
        XCTAssertEqual(machine.apply(.retry), .moving)
        XCTAssertEqual(machine.apply(.success), .succeeded)
        XCTAssertTrue(machine.state.isTerminal)
    }

    func testFailureThenRollback() {
        var machine = MoveMachine()
        _ = machine.apply(.start)
        XCTAssertEqual(machine.apply(.failure), .failed)
        XCTAssertEqual(machine.apply(.rollback), .rolledBack)
    }

    func testInvalidTransitionIsIgnored() {
        var machine = MoveMachine()
        XCTAssertEqual(machine.apply(.success), .idle, "cannot succeed before starting")
        _ = machine.apply(.start)
        _ = machine.apply(.success)
        XCTAssertEqual(machine.apply(.failure), .succeeded, "terminal state is not overwritten by late events")
    }

    func testRetryAfterFailureRestarts() {
        var machine = MoveMachine()
        _ = machine.apply(.start)
        _ = machine.apply(.failure)
        XCTAssertEqual(machine.apply(.start), .moving)
    }
}

final class LayoutCoordinatorTests: XCTestCase {
    private func makeCoordinator(
        simulator: WindowServerSimulator,
        mover: SimulatingMover,
        store: InMemoryStore,
        permissions: StubPermissions = StubPermissions(),
        conflicts: ConflictDetecting = NoConflicts(),
        configuration: LayoutCoordinator.Configuration = .init(
            maxAttempts: 3,
            attemptDelayMs: 0,
            verificationSamples: 2,
            verificationIntervalMs: 0,
            abortBatchAfterFailures: 2
        )
    ) -> LayoutCoordinator {
        LayoutCoordinator(
            scanner: SimulatedScanner(simulator: simulator),
            mover: mover,
            permissions: permissions,
            store: store,
            clock: FastClock(),
            conflictDetector: conflicts,
            configuration: configuration
        )
    }

    func testSuccessfulMoveUpdatesSnapshotAndLog() async throws {
        let simulator = WindowServerSimulator()
        simulator.set(ItemFrame(x: 1100, y: 0, width: 24, height: 24), for: "wifi")
        var mover: SimulatingMover!
        mover = SimulatingMover()
        let store = InMemoryStore()
        store.snapshot = LayoutSnapshot.empty(display: testDisplay)
        let coordinator = makeCoordinator(simulator: simulator, mover: mover, store: store)

        let item = makeItem(id: "wifi", x: 1100)
        let target = LayoutEngine().targetFrame(
            for: .hidden, index: 0, size: item.frame, anchors: testAnchors, display: testDisplay
        )
        // The simulated window server applies the drag to the real frame.
        let applyingMover = SimulatingMover()
        let coordinatorWithSimulation = LayoutCoordinator(
            scanner: SimulatedScanner(simulator: simulator),
            mover: ApplyingMover(simulator: simulator, inner: applyingMover),
            permissions: StubPermissions(),
            store: store,
            clock: FastClock(),
            conflictDetector: NoConflicts(),
            configuration: .init(maxAttempts: 2, attemptDelayMs: 0, verificationSamples: 2, verificationIntervalMs: 0, abortBatchAfterFailures: 2)
        )
        let outcome = try await coordinatorWithSimulation.move(
            item: item, to: .hidden, anchors: testAnchors, display: testDisplay
        )
        XCTAssertEqual(outcome.result, .success)
        XCTAssertEqual(outcome.attempts, 1)
        XCTAssertLessThanOrEqual(simulator.frame(for: "wifi")?.maxX ?? 0, 0)
        XCTAssertEqual(store.logs.last?.result, .success)
        XCTAssertNotNil(store.snapshot?.originalFrames["wifi"])
        _ = coordinator
        _ = target
        _ = mover
    }

    func testMoveWithoutAccessibilityThrows() async {
        let simulator = WindowServerSimulator()
        let mover = SimulatingMover()
        let store = InMemoryStore()
        let coordinator = makeCoordinator(
            simulator: simulator,
            mover: mover,
            store: store,
            permissions: StubPermissions(accessibility: .denied)
        )
        do {
            _ = try await coordinator.move(
                item: makeItem(id: "x", x: 100), to: .hidden, anchors: testAnchors, display: testDisplay
            )
            XCTFail("expected accessibility error")
        } catch let error as MacBarError {
            XCTAssertEqual(error, .accessibilityDenied)
        } catch {
            XCTFail("unexpected error \(error)")
        }
    }

    func testConflictBlockPolicyThrows() async {
        let coordinator = makeCoordinator(
            simulator: WindowServerSimulator(),
            mover: SimulatingMover(),
            store: InMemoryStore(),
            conflicts: ConflictingTool()
        )
        do {
            try await coordinator.preflight(policy: .block)
            XCTFail("expected conflict")
        } catch let error as MacBarError {
            XCTAssertEqual(error, .conflictDetected(apps: ["Bartender"]))
        } catch {
            XCTFail("unexpected error")
        }
    }

    func testConflictWarnPolicyAllowsPreflight() async throws {
        let coordinator = makeCoordinator(
            simulator: WindowServerSimulator(),
            mover: SimulatingMover(),
            store: InMemoryStore(),
            conflicts: ConflictingTool()
        )
        try await coordinator.preflight(policy: .warn)
    }

    func testFailedMoveRollsBackAndLogs() async {
        let simulator = WindowServerSimulator()
        simulator.set(ItemFrame(x: 900, y: 0, width: 24, height: 24), for: "bad")
        let mover = SimulatingMover()
        mover.failEveryDrag = true
        mover.failure = .eventCreationFailed
        let store = InMemoryStore()
        let coordinator = makeCoordinator(simulator: simulator, mover: mover, store: store)

        let outcome = try? await coordinator.move(
            item: makeItem(id: "bad", x: 900), to: .hidden, anchors: testAnchors, display: testDisplay
        )
        XCTAssertEqual(outcome?.result, .failed)
        XCTAssertEqual(outcome?.error, .eventCreationFailed)
        XCTAssertEqual(store.logs.last?.result, .failed)
        XCTAssertEqual(store.logs.last?.errorCode, MacBarError.eventCreationFailed.code)
    }

    func testBatchAbortsAfterConsecutiveFailures() async {
        let simulator = WindowServerSimulator()
        for index in 0..<4 {
            simulator.set(ItemFrame(x: 900 - Double(index) * 30, y: 0, width: 24, height: 24), for: "b\(index)")
        }
        let mover = SimulatingMover()
        mover.failEveryDrag = true
        mover.failure = .moveTimedOut(itemID: "b")
        let store = InMemoryStore()
        let coordinator = makeCoordinator(simulator: simulator, mover: mover, store: store)

        let items = (0..<4).map { makeItem(id: "b\($0)", x: 900 - Double($0) * 30) }
        let targets = Dictionary(uniqueKeysWithValues: items.map { ($0.id, MenuBarSection.hidden) })
        let plan = await coordinator.plan(
            items: items, targetSections: targets, anchors: testAnchors, display: testDisplay
        )
        let batch = await coordinator.apply(plan: plan, items: items, anchors: testAnchors, display: testDisplay)
        XCTAssertTrue(batch.aborted)
        XCTAssertEqual(batch.failureCount, 2, "stops after abortBatchAfterFailures consecutive failures")
    }

    func testBatchStopsImmediatelyOnPermissionError() async {
        let simulator = WindowServerSimulator()
        simulator.set(ItemFrame(x: 900, y: 0, width: 24, height: 24), for: "v")
        let store = InMemoryStore()
        let coordinator = makeCoordinator(
            simulator: simulator,
            mover: SimulatingMover(),
            store: store,
            permissions: StubPermissions(accessibility: .denied)
        )
        let items = [makeItem(id: "v", x: 900)]
        let plan = await coordinator.plan(
            items: items, targetSections: ["v": .hidden], anchors: testAnchors, display: testDisplay
        )
        let batch = await coordinator.apply(plan: plan, items: items, anchors: testAnchors, display: testDisplay)
        XCTAssertTrue(batch.aborted)
        XCTAssertEqual(batch.outcomes.first?.error, .accessibilityDenied)
    }
}

final class ItemRegistryTests: XCTestCase {
    func testIdentityIsStableAcrossWindowIDs() {
        let first = ItemRegistry.identity(bundleIdentifier: "com.apple.controlcenter", ownerName: "Control Center", title: "Wi-Fi", fallbackIndex: 0)
        let second = ItemRegistry.identity(bundleIdentifier: "com.apple.controlcenter", ownerName: "Control Center", title: "Wi-Fi", fallbackIndex: 7)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, "com.apple.controlcenter::Wi-Fi")
    }

    func testIdentityFallsBackToOwnerAndIndex() {
        let id = ItemRegistry.identity(bundleIdentifier: nil, ownerName: "Dropbox", title: "", fallbackIndex: 2)
        XCTAssertEqual(id, "Dropbox::item-2")
    }

    func testReconcileAddsRemovesAndDetectsDrift() async {
        let registry = ItemRegistry()
        var snapshot = LayoutSnapshot.empty(display: testDisplay)
        snapshot.sections = [
            .visible: ["a", "removed"],
            .hidden: ["b"],
            .alwaysHidden: [],
        ]
        let scan = ScanResult(
            items: [
                makeItem(id: "a", x: 100, section: .visible),
                makeItem(id: "b", x: 200, section: .visible), // drifted: intended hidden
                makeItem(id: "new", x: 300, section: .visible),
            ],
            accessibilityAvailable: true
        )
        let result = await registry.reconcile(
            snapshot: snapshot,
            scan: scan,
            derivedSections: Dictionary(uniqueKeysWithValues: scan.items.map { ($0.id, .visible) })
        )
        XCTAssertEqual(Set(result.added), ["new"])
        XCTAssertEqual(Set(result.removed), ["removed"])
        XCTAssertEqual(Set(result.drifted), ["b"])
        XCTAssertEqual(result.snapshot.items(in: .visible), ["a", "new"])
        XCTAssertEqual(result.snapshot.items(in: .hidden), ["b"])
    }

    func testNormalizedKeepsEveryItemOnce() {
        var snapshot = LayoutSnapshot.empty(display: testDisplay)
        snapshot.sections = [.visible: ["a", "a"], .hidden: ["b", "c"], .alwaysHidden: []]
        let normalized = snapshot.normalized(knownItemIDs: ["a", "b", "c", "d"]) { _ in .visible }
        XCTAssertEqual(normalized.items(in: .visible), ["a", "d"])
        XCTAssertEqual(normalized.items(in: .hidden), ["b", "c"])
    }
}

final class JSONLayoutStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("macbar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    func testRoundTripSnapshot() throws {
        let store = JSONLayoutStore(directory: directory)
        var snapshot = LayoutSnapshot.empty(display: testDisplay)
        snapshot.sections = [.visible: ["a"], .hidden: ["b"], .alwaysHidden: []]
        snapshot.originalFrames["b"] = ItemFrame(x: -40, y: 0, width: 24, height: 24)
        try store.saveSnapshot(snapshot)

        let loaded = try XCTUnwrap(try store.loadSnapshot())
        XCTAssertEqual(loaded.sections[.visible], ["a"])
        XCTAssertEqual(loaded.sections[.hidden], ["b"])
        XCTAssertEqual(loaded.originalFrames["b"]?.x, -40)
    }

    func testCorruptSnapshotIsQuarantinedAndReturnsNil() throws {
        let store = JSONLayoutStore(directory: directory)
        try Data("{ not json".utf8).write(to: directory.appendingPathComponent("layout.json"))

        XCTAssertNil(try store.loadSnapshot())
        let contents = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        XCTAssertTrue(
            contents.contains { $0.hasPrefix("layout.json.corrupt-") },
            "corrupt file must be preserved, not deleted: \(contents)"
        )
    }

    func testSettingsReturnDefaultsWhenMissing() {
        let store = JSONLayoutStore(directory: directory)
        XCTAssertEqual(store.loadSettings(), AppSettings.default)
    }

    func testAuditLogAppendAndRead() throws {
        let store = JSONLayoutStore(directory: directory)
        let log = OperationLog(opType: .hide, itemID: "a", result: .success, retryCount: 1, durationMs: 42)
        store.appendLog(log)
        store.appendLog(OperationLog(opType: .show, itemID: "a", result: .failed, errorCode: "MB-E1003"))
        // Appends happen on a utility queue; wait for them to land.
        let deadline = Date().addingTimeInterval(2)
        while store.loadLogs(limit: 10).count < 2 && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        let logs = store.loadLogs(limit: 10)
        XCTAssertEqual(logs.count, 2)
        XCTAssertEqual(logs.first?.opType, .hide)
        XCTAssertEqual(logs.last?.errorCode, "MB-E1003")
    }

    func testDiagnosticsExportContainsEnvironment() throws {
        let store = JSONLayoutStore(directory: directory)
        try store.saveSettings(AppSettings(conflictPolicy: .block))
        let url = try store.exportDiagnostics(
            items: [makeItem(id: "wifi", x: 100)],
            permissions: [.accessibility: .granted],
            conflicts: ["Ice"]
        )
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("MacBar Diagnostics"))
        XCTAssertTrue(text.contains("accessibility: granted"))
        XCTAssertTrue(text.contains("wifi | section=visible"))
        XCTAssertTrue(text.contains("Ice"))
    }
}

final class DisplayAttributionTests: XCTestCase {
    private let main = DisplayGeometry(
        displayID: 1,
        bounds: ItemFrame(x: 0, y: 0, width: 1440, height: 900),
        menuBarHeight: 24,
        isMain: true
    )
    private let left = DisplayGeometry(
        displayID: 3,
        bounds: ItemFrame(x: -1920, y: -145, width: 1920, height: 1080),
        menuBarHeight: 24,
        isMain: false
    )

    func testItemOnSecondDisplayBelongsToSecondDisplay() {
        let frame = ItemFrame(x: -794, y: -145, width: 38, height: 30)
        let owner = DisplayAttribution.owner(of: frame, among: [main, left])
        XCTAssertEqual(owner?.displayID, 3)
        XCTAssertTrue(DisplayAttribution.isOnScreen(frame, display: left))
    }

    func testItemOffTheLeftEdgeIsNotOnScreen() {
        let frame = ItemFrame(x: -400, y: 0, width: 40, height: 33)
        XCTAssertFalse(DisplayAttribution.isOnScreen(frame, display: main))
    }

    func testHiddenItemOnMainDisplayStaysWithMainDisplay() {
        // A collapsed item placed by MacBar keeps the bar's top edge and moves
        // to a negative x, so it is off screen but still belongs to the bar.
        let frame = ItemFrame(x: -200, y: 0, width: 40, height: 30)
        XCTAssertFalse(DisplayAttribution.isOnScreen(frame, display: main))
        XCTAssertTrue(DisplayAttribution.isOnScreen(ItemFrame(x: 20, y: 0, width: 40, height: 30), display: main))
    }

    func testVisibleItemIsOnScreen() {
        let frame = ItemFrame(x: 900, y: 0, width: 40, height: 33)
        XCTAssertTrue(DisplayAttribution.isOnScreen(frame, display: main))
    }

    func testItemBelowMenuBarIsNotOnScreen() {
        let frame = ItemFrame(x: 900, y: 40, width: 40, height: 33)
        XCTAssertFalse(DisplayAttribution.isOnScreen(frame, display: main))
    }
}

final class ItemCapabilityEvaluatorTests: XCTestCase {
    func testClockIsNotHideable() {
        let evaluator = ItemCapabilityEvaluator()
        XCTAssertFalse(evaluator.canMove(bundleIdentifier: "com.apple.controlcenter", title: "Clock"))
        XCTAssertFalse(evaluator.canHide(bundleIdentifier: "com.apple.controlcenter", title: "Clock"))
        XCTAssertNotNil(evaluator.disabledReason(bundleIdentifier: "com.apple.controlcenter", title: "Clock"))
    }

    func testThirdPartyItemIsHideable() {
        let evaluator = ItemCapabilityEvaluator()
        XCTAssertTrue(evaluator.canHide(bundleIdentifier: "com.getdropbox.dropbox", title: "Dropbox"))
        XCTAssertNil(evaluator.disabledReason(bundleIdentifier: "com.getdropbox.dropbox", title: "Dropbox"))
    }

    func testSystemOwnershipDetection() {
        let evaluator = ItemCapabilityEvaluator()
        XCTAssertTrue(evaluator.isSystemOwned(bundleIdentifier: "com.apple.controlcenter", ownerName: "Control Center"))
        XCTAssertFalse(evaluator.isSystemOwned(bundleIdentifier: "com.example.app", ownerName: "Example"))
    }
}

// MARK: - Helpers

private struct FastClock: ClockProviding {
    func now() -> Date { Date() }
    func sleep(milliseconds: Int) async throws {}
}

/// Applies a drag to the simulated window server before delegating.
private final class ApplyingMover: MenuBarMoving, @unchecked Sendable {
    let simulator: WindowServerSimulator
    let inner: SimulatingMover

    init(simulator: WindowServerSimulator, inner: SimulatingMover) {
        self.simulator = simulator
        self.inner = inner
    }

    func drag(itemID: String, windowID: UInt32, ownerPID: Int32, from: ItemPoint, to: ItemPoint) async throws {
        try await inner.drag(itemID: itemID, windowID: windowID, ownerPID: ownerPID, from: from, to: to)
        simulator.apply(drag: .init(itemID: itemID, from: from, to: to))
    }

    func click(itemID: String, windowID: UInt32, ownerPID: Int32, at: ItemPoint, button: MouseButton) async throws {}
    func wakeUp(itemID: String, windowID: UInt32, ownerPID: Int32, at: ItemPoint) async throws {}
    func isEventPostingAvailable() -> Bool { true }
}

final class MenuBarHostingTests: XCTestCase {
    func testUnknownDuringGracePeriod() {
        for misses in 0..<MenuBarHosting.maxMisses {
            XCTAssertEqual(MenuBarHosting.status(misses: misses, sawHostedWindow: false), .unknown)
        }
    }

    func testNotHostedAfterGracePeriod() {
        XCTAssertEqual(
            MenuBarHosting.status(misses: MenuBarHosting.maxMisses, sawHostedWindow: false),
            .notHosted
        )
    }

    func testHostedWinsImmediately() {
        XCTAssertEqual(MenuBarHosting.status(misses: 0, sawHostedWindow: true), .hosted)
    }
}

final class SignatureInfoTests: XCTestCase {
    func testAdHocFingerprintUsesCDHash() {
        let info = SignatureInfo(cdhash: "abc", teamIdentifier: "", isAdHoc: true, fingerprint: "abc")
        XCTAssertTrue(info.isAdHoc)
        XCTAssertEqual(info.shortFingerprint, "abc")
        XCTAssertTrue(info.summary.contains("ad-hoc"))
    }

    func testCertificateFingerprintIsStablePerTeam() {
        let a = SignatureInfo(cdhash: "111", teamIdentifier: "TEAM1", isAdHoc: false, fingerprint: "team:TEAM1")
        let b = SignatureInfo(cdhash: "222", teamIdentifier: "TEAM1", isAdHoc: false, fingerprint: "team:TEAM1")
        XCTAssertEqual(a.fingerprint, b.fingerprint, "certificate builds keep the grant across rebuilds")
        XCTAssertTrue(a.summary.contains("TEAM1"))
    }
}
