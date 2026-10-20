import Foundation

/// Positions of the three separator items MacBar owns.
///
/// The anchors are ordinary status items created by MacBar. Items pushed to the
/// right of `hiddenX` end up outside the screen and therefore invisible. When a
/// layout is computed before anchors exist (for example on first launch) they
/// are derived from the menu bar geometry.
public struct LayoutAnchors: Codable, Hashable, Sendable {
    public var visibleX: Double
    public var hiddenX: Double
    public var alwaysHiddenX: Double?

    public init(visibleX: Double, hiddenX: Double, alwaysHiddenX: Double? = nil) {
        self.visibleX = visibleX
        self.hiddenX = hiddenX
        self.alwaysHiddenX = alwaysHiddenX
    }

    public static let zero = LayoutAnchors(visibleX: 0, hiddenX: 0, alwaysHiddenX: nil)
}

/// A persisted snapshot of the intended menu bar layout.
public struct LayoutSnapshot: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var snapshotId: UUID
    public var createdAt: Date
    public var updatedAt: Date
    public var displayID: UInt32
    public var screenWidth: Double
    public var menuBarHeight: Double
    public var anchors: LayoutAnchors
    public var sections: [MenuBarSection: [String]]
    public var originalFrames: [String: ItemFrame]
    public var appVersion: String

    public init(
        schemaVersion: Int = LayoutSnapshot.currentSchemaVersion,
        snapshotId: UUID = UUID(),
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        displayID: UInt32 = 0,
        screenWidth: Double = 0,
        menuBarHeight: Double = 0,
        anchors: LayoutAnchors = .zero,
        sections: [MenuBarSection: [String]] = [:],
        originalFrames: [String: ItemFrame] = [:],
        appVersion: String = MacBarVersion.current
    ) {
        self.schemaVersion = schemaVersion
        self.snapshotId = snapshotId
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.displayID = displayID
        self.screenWidth = screenWidth
        self.menuBarHeight = menuBarHeight
        self.anchors = anchors
        self.sections = sections
        self.originalFrames = originalFrames
        self.appVersion = appVersion
    }

    public func items(in section: MenuBarSection) -> [String] {
        sections[section] ?? []
    }

    public func section(of itemID: String) -> MenuBarSection? {
        for section in MenuBarSection.allCases where items(in: section).contains(itemID) {
            return section
        }
        return nil
    }

    public mutating func remove(itemID: String) {
        for section in MenuBarSection.allCases {
            sections[section]?.removeAll { $0 == itemID }
        }
        originalFrames[itemID] = nil
    }

    public mutating func insert(itemID: String, into section: MenuBarSection, at index: Int? = nil) {
        remove(itemID: itemID)
        var list = sections[section] ?? []
        let clamped = min(max(index ?? list.count, 0), list.count)
        list.insert(itemID, at: clamped)
        sections[section] = list
    }

    public mutating func move(itemID: String, to section: MenuBarSection) {
        insert(itemID: itemID, into: section)
    }

    /// A snapshot with no items, used when no file exists yet.
    public static func empty(display: DisplayGeometry) -> LayoutSnapshot {
        LayoutSnapshot(
            displayID: display.displayID,
            screenWidth: display.bounds.width,
            menuBarHeight: display.menuBarHeight,
            sections: [:],
            originalFrames: [:]
        )
    }

    /// Returns a copy whose sections contain every item exactly once, keeping
    /// existing order and appending unknown items to the visible section.
    public func normalized(knownItemIDs: [String], sectionResolver: (String) -> MenuBarSection) -> LayoutSnapshot {
        var result = self
        var seen = Set<String>()
        for section in MenuBarSection.allCases {
            var list: [String] = []
            for id in items(in: section) where !seen.contains(id) {
                seen.insert(id)
                if knownItemIDs.contains(id) {
                    list.append(id)
                }
            }
            result.sections[section] = list
        }
        for id in knownItemIDs where !seen.contains(id) {
            let section = sectionResolver(id)
            result.sections[section, default: []].append(id)
            seen.insert(id)
        }
        return result
    }
}

/// The intent of a layout computation: where each item should go and why some
/// items were skipped.
public struct LayoutPlan: Sendable, Equatable {
    public var moves: [PlannedMove]
    public var skipped: [SkippedMove]
    public var targetSections: [String: MenuBarSection]

    public init(moves: [PlannedMove] = [], skipped: [SkippedMove] = [], targetSections: [String: MenuBarSection] = [:]) {
        self.moves = moves
        self.skipped = skipped
        self.targetSections = targetSections
    }

    public static let empty = LayoutPlan()

    public var isEmpty: Bool { moves.isEmpty && skipped.isEmpty }
}

public struct PlannedMove: Sendable, Equatable, Identifiable {
    public var id: String { itemID }
    public var itemID: String
    public var from: MenuBarSection
    public var to: MenuBarSection
    public var targetFrame: ItemFrame

    public init(itemID: String, from: MenuBarSection, to: MenuBarSection, targetFrame: ItemFrame) {
        self.itemID = itemID
        self.from = from
        self.to = to
        self.targetFrame = targetFrame
    }
}

public struct SkippedMove: Sendable, Equatable {
    public enum Reason: String, Sendable {
        case notHideable
        case notMovable
        case notFound
        case anotherDisplay
        case alreadyInPlace
    }

    public var itemID: String
    public var reason: Reason

    public init(itemID: String, reason: Reason) {
        self.itemID = itemID
        self.reason = reason
    }
}
