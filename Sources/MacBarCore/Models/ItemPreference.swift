import Foundation

/// Per-item user preferences that must survive application restarts even when
/// the owning application is not running.
public struct ItemPreference: Codable, Hashable, Sendable, Identifiable {
    public var itemID: String
    public var alias: String?
    public var pinnedSection: MenuBarSection?
    public var hiddenFromList: Bool
    public var updatedAt: Date

    public var id: String { itemID }

    public init(
        itemID: String,
        alias: String? = nil,
        pinnedSection: MenuBarSection? = nil,
        hiddenFromList: Bool = false,
        updatedAt: Date = Date()
    ) {
        self.itemID = itemID
        self.alias = alias
        self.pinnedSection = pinnedSection
        self.hiddenFromList = hiddenFromList
        self.updatedAt = updatedAt
    }
}

/// Persisted collection of per-item preferences.
public struct PreferencesFile: Codable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var items: [String: ItemPreference]
    public var updatedAt: Date

    public init(
        schemaVersion: Int = PreferencesFile.currentSchemaVersion,
        items: [String: ItemPreference] = [:],
        updatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.items = items
        self.updatedAt = updatedAt
    }

    public func pinnedSection(for itemID: String) -> MenuBarSection? {
        items[itemID]?.pinnedSection
    }

    public func isHiddenFromList(_ itemID: String) -> Bool {
        items[itemID]?.hiddenFromList ?? false
    }
}
