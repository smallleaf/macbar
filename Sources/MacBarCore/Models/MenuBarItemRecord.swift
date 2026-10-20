import Foundation

/// A single status item currently present in the menu bar.
///
/// `id` is stable across window ID changes: it is derived from the owning
/// application plus the item title, mirroring the namespace+title model used by
/// established menu bar managers. `windowID` is only valid for the lifetime of
/// the window and must never be persisted as an identity.
public struct MenuBarItemRecord: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var windowID: UInt32
    public var ownerPID: Int32
    public var ownerName: String
    public var bundleIdentifier: String?
    public var title: String
    public var itemDescription: String
    public var frame: ItemFrame
    public var displayID: UInt32
    public var isOnScreen: Bool
    public var isMovable: Bool
    public var isHideable: Bool
    public var isSystemOwned: Bool
    public var section: MenuBarSection
    public var alias: String?
    public var isPinned: Bool
    public var isDrifted: Bool

    public init(
        id: String,
        windowID: UInt32,
        ownerPID: Int32,
        ownerName: String,
        bundleIdentifier: String?,
        title: String,
        itemDescription: String = "",
        frame: ItemFrame,
        displayID: UInt32,
        isOnScreen: Bool,
        isMovable: Bool = true,
        isHideable: Bool = true,
        isSystemOwned: Bool = false,
        section: MenuBarSection = .visible,
        alias: String? = nil,
        isPinned: Bool = false,
        isDrifted: Bool = false
    ) {
        self.id = id
        self.windowID = windowID
        self.ownerPID = ownerPID
        self.ownerName = ownerName
        self.bundleIdentifier = bundleIdentifier
        self.title = title
        self.itemDescription = itemDescription
        self.frame = frame
        self.displayID = displayID
        self.isOnScreen = isOnScreen
        self.isMovable = isMovable
        self.isHideable = isHideable
        self.isSystemOwned = isSystemOwned
        self.section = section
        self.alias = alias
        self.isPinned = isPinned
        self.isDrifted = isDrifted
    }

    /// Name shown to the user: alias, then accessibility title, then the
    /// owning application name.
    public var displayName: String {
        if let alias, !alias.isEmpty {
            return alias
        }
        if !title.isEmpty {
            return title
        }
        if !itemDescription.isEmpty {
            return itemDescription
        }
        return ownerName
    }

    /// Secondary line: owning app, with the accessibility description only when
    /// it adds information.
    public var subtitle: String {
        guard !title.isEmpty, title != ownerName else {
            return ownerName
        }
        return ownerName
    }

    public var isOffscreen: Bool {
        !isOnScreen
    }
}

/// Result of a menu bar scan.
public struct ScanResult: Sendable, Equatable {
    public var items: [MenuBarItemRecord]
    public var accessibilityAvailable: Bool
    public var scannedAt: Date

    public init(items: [MenuBarItemRecord], accessibilityAvailable: Bool, scannedAt: Date = Date()) {
        self.items = items
        self.accessibilityAvailable = accessibilityAvailable
        self.scannedAt = scannedAt
    }

    public static let empty = ScanResult(items: [], accessibilityAvailable: false)
}
