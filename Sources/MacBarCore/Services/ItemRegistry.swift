import Foundation

/// Owns the canonical list of known items, assigns stable identifiers and keeps
/// the layout snapshot in sync with what is actually on screen.
///
/// Identity is `bundleIdentifier::title`. When an application restarts its
/// window ID changes but the identity does not, so preferences and section
/// membership survive. Items without an accessibility title fall back to their
/// window index within the owning namespace.
public actor ItemRegistry {
    public struct SnapshotReconciliation: Sendable, Equatable {
        public var snapshot: LayoutSnapshot
        public var added: [String]
        public var removed: [String]
        public var drifted: [String]
    }

    private let evaluator: ItemCapabilityEvaluator
    private var lastScan: ScanResult = .empty
    private var preferences: PreferencesFile

    public init(evaluator: ItemCapabilityEvaluator = ItemCapabilityEvaluator(), preferences: PreferencesFile = PreferencesFile()) {
        self.evaluator = evaluator
        self.preferences = preferences
    }

    public var currentItems: [MenuBarItemRecord] { lastScan.items }

    public func updatePreferences(_ preferences: PreferencesFile) {
        self.preferences = preferences
    }

    /// Applies user preferences (alias, pin, hidden-from-list) onto raw records.
    public func decorate(_ records: [MenuBarItemRecord]) -> [MenuBarItemRecord] {
        records.map { record in
            var copy = record
            if let preference = preferences.items[record.id] {
                copy.alias = preference.alias
                copy.isPinned = preference.pinnedSection != nil
            }
            return copy
        }
    }

    /// Records a fresh scan and returns the items with preferences applied.
    public func absorb(scan: ScanResult, pinnedSections: [String: MenuBarSection]) -> [MenuBarItemRecord] {
        let decorated = decorate(scan.items).map { record -> MenuBarItemRecord in
            guard let pinned = pinnedSections[record.id] else { return record }
            var copy = record
            copy.section = pinned
            copy.isPinned = true
            return copy
        }
        lastScan = ScanResult(items: decorated, accessibilityAvailable: scan.accessibilityAvailable, scannedAt: scan.scannedAt)
        return decorated
    }

    /// Items visible in the management panel.
    public var panelItems: [MenuBarItemRecord] {
        filterForPanel(lastScan.items)
    }

    public func filterForPanel(_ items: [MenuBarItemRecord], includeSystemItems: Bool = true) -> [MenuBarItemRecord] {
        items.filter { item in
            if preferences.isHiddenFromList(item.id) { return false }
            if item.ownerName == "MacBar" || item.ownerName == "Window Server" { return false }
            if !includeSystemItems && item.isSystemOwned { return false }
            return true
        }
    }

    /// Reconciles a persisted snapshot against the current scan.
    ///
    /// - Items in the snapshot that disappeared are removed (the app was quit or
    ///   the icon was removed by its owner).
    /// - Items present on screen but absent from the snapshot are appended to the
    ///   visible section.
    /// - Items whose on-screen state contradicts their section are reported as
    ///   drifted so the coordinator can repair them.
    public func reconcile(
        snapshot: LayoutSnapshot,
        scan: ScanResult,
        derivedSections: [String: MenuBarSection]
    ) -> SnapshotReconciliation {
        let currentIDs = Set(scan.items.map(\.id))
        let knownIDs = scan.items.map(\.id)

        let removed = snapshot.sections.values.flatMap { $0 }.filter { !currentIDs.contains($0) }
        let existingIDs = Set(snapshot.sections.values.flatMap { $0 })
        let added = knownIDs.filter { !existingIDs.contains($0) }

        var result = snapshot.normalized(knownItemIDs: knownIDs) { itemID in
            derivedSections[itemID] ?? .visible
        }
        for itemID in removed {
            result.remove(itemID: itemID)
        }

        var drifted: [String] = []
        for item in scan.items {
            guard let section = result.section(of: item.id) else { continue }
            if section != item.section {
                drifted.append(item.id)
            }
        }

        result.updatedAt = Date()
        return SnapshotReconciliation(snapshot: result, added: added, removed: removed, drifted: drifted)
    }

    /// Builds a stable identity for an item.
    public static func identity(bundleIdentifier: String?, ownerName: String, title: String, fallbackIndex: Int) -> String {
        let namespace = bundleIdentifier?.isEmpty == false ? bundleIdentifier! : ownerName
        let name = title.isEmpty ? "item-\(fallbackIndex)" : title
        return "\(namespace)::\(name)"
    }
}
