import Foundation

/// A rectangle expressed in Core Graphics global coordinates.
///
/// The menu bar lives in a coordinate space whose origin is the top-left of the
/// main display, with `y` growing downwards. AppKit uses a bottom-left origin,
/// so conversions must happen at the system boundary.
public struct ItemFrame: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public init(origin: ItemPoint, size: (width: Double, height: Double)) {
        self.init(x: origin.x, y: origin.y, width: size.width, height: size.height)
    }

    public static let zero = ItemFrame(x: 0, y: 0, width: 0, height: 0)

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var midX: Double { x + width / 2 }
    public var midY: Double { y + height / 2 }
    public var area: Double { max(0, width) * max(0, height) }

    public var center: ItemPoint {
        ItemPoint(x: midX, y: midY)
    }

    public func contains(_ point: ItemPoint) -> Bool {
        point.x >= minX && point.x <= maxX && point.y >= minY && point.y <= maxY
    }

    public func intersects(_ other: ItemFrame) -> Bool {
        minX < other.maxX && maxX > other.minX && minY < other.maxY && maxY > other.minY
    }

    /// Returns a frame whose origin is shifted so that the center lands on `point`.
    public func centered(at point: ItemPoint) -> ItemFrame {
        ItemFrame(x: point.x - width / 2, y: point.y - height / 2, width: width, height: height)
    }

    /// A small tolerance is applied because the window server rounds frames to
    /// points when items are moved.
    public func isApproximatelyEqual(to other: ItemFrame, tolerance: Double = 1.5) -> Bool {
        abs(x - other.x) <= tolerance
            && abs(y - other.y) <= tolerance
            && abs(width - other.width) <= tolerance
            && abs(height - other.height) <= tolerance
    }
}

/// A point in Core Graphics global coordinates.
public struct ItemPoint: Codable, Hashable, Sendable {
    public var x: Double
    public var y: Double

    public init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }

    public static let zero = ItemPoint(x: 0, y: 0)
}

/// Geometry of a display that owns a menu bar.
public struct DisplayGeometry: Codable, Hashable, Sendable {
    public var displayID: UInt32
    public var bounds: ItemFrame
    public var menuBarHeight: Double
    public var isMain: Bool

    public init(displayID: UInt32, bounds: ItemFrame, menuBarHeight: Double, isMain: Bool) {
        self.displayID = displayID
        self.bounds = bounds
        self.menuBarHeight = menuBarHeight
        self.isMain = isMain
    }

    public var menuBarMidY: Double { bounds.minY + menuBarHeight / 2 }

    public static let unknown = DisplayGeometry(
        displayID: 0,
        bounds: ItemFrame(x: 0, y: 0, width: 1440, height: 900),
        menuBarHeight: 24,
        isMain: true
    )
}
