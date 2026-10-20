import Foundation

/// Repairs the layout after launch, when the user asks for a reset, or when the
/// emergency shortcut fires.
public actor RestoreService {
    public struct Result: Sendable, Equatable {
        public var repaired: [String]
        public var failed: [String]
        public var skipped: [String]

        public static let empty = Result(repaired: [], failed: [], skipped: [])
    }

    private let scanner: MenuBarScanning
    private let coordinator: LayoutCoordinator
    private let store: LayoutStoring
    private let engine: LayoutEngine

    public init(
        scanner: MenuBarScanning,
        coordinator: LayoutCoordinator,
        store: LayoutStoring,
        engine: LayoutEngine = LayoutEngine()
    ) {
        self.scanner = scanner
        self.coordinator = coordinator
        self.store = store
        self.engine = engine
    }

    /// Moves every item that is out of place back to its intended section.
    public func heal(
        items: [MenuBarItemRecord],
        snapshot: LayoutSnapshot,
        anchors: LayoutAnchors,
        display: DisplayGeometry,
        onlyDrifted: Bool = true
    ) async -> Result {
        let targetSections = Dictionary(
            uniqueKeysWithValues: snapshot.sections.flatMap { section, ids in
                ids.map { ($0, section) }
            }
        )
        let candidates: [MenuBarItemRecord]
        if onlyDrifted {
            candidates = items.filter { item in
                guard let intended = targetSections[item.id] else { return false }
                return !engine.isAt(item: item, section: intended, anchors: anchors)
            }
        } else {
            candidates = items
        }
        guard !candidates.isEmpty else { return .empty }

        let plan = await coordinator.plan(
            items: candidates,
            targetSections: targetSections.filter { id, _ in candidates.contains { $0.id == id } },
            anchors: anchors,
            display: display
        )
        let batch = await coordinator.apply(plan: plan, items: candidates, anchors: anchors, display: display, logType: .selfHeal)
        let repaired = batch.outcomes.filter(\.isSuccess).map(\.itemID)
        let failed = batch.outcomes.filter(\.isFailure).map(\.itemID)
        let skipped = batch.outcomes.filter { $0.result == .skipped }.map(\.itemID)
        return Result(repaired: repaired, failed: failed, skipped: skipped)
    }

    /// Moves every managed item back to the visible section, preserving order.
    public func reset(
        items: [MenuBarItemRecord],
        anchors: LayoutAnchors,
        display: DisplayGeometry
    ) async -> Result {
        let movable = items.filter { $0.isMovable && $0.isHideable && $0.section != .visible }
        guard !movable.isEmpty else { return .empty }
        let targets = Dictionary(uniqueKeysWithValues: movable.map { ($0.id, MenuBarSection.visible) })
        let plan = await coordinator.plan(
            items: movable,
            targetSections: targets,
            anchors: anchors,
            display: display,
            includeAlreadyPlaced: true
        )
        let batch = await coordinator.apply(plan: plan, items: movable, anchors: anchors, display: display, logType: .reset)
        let repaired = batch.outcomes.filter(\.isSuccess).map(\.itemID)
        let failed = batch.outcomes.filter(\.isFailure).map(\.itemID)
        let skipped = batch.outcomes.filter { $0.result == .skipped }.map(\.itemID)
        return Result(repaired: repaired, failed: failed, skipped: skipped)
    }

    /// Restores recorded original frames for items that were moved by MacBar.
    public func restoreOriginalFrames(items: [MenuBarItemRecord], snapshot: LayoutSnapshot) async -> Result {
        var repaired: [String] = []
        var failed: [String] = []
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let ids = Array(snapshot.originalFrames.keys)
        for id in ids {
            guard let item = byID[id], let frame = snapshot.originalFrames[id] else { continue }
            if item.frame.isApproximatelyEqual(to: frame) {
                continue
            }
            let outcome = await coordinator.restore(item: item, originalFrame: frame)
            if outcome.isSuccess {
                repaired.append(id)
            } else {
                failed.append(id)
            }
        }
        return Result(repaired: repaired, failed: failed, skipped: [])
    }
}
