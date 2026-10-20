import Foundation

/// Assigns status item windows to the display whose menu bar owns them.
///
/// Each display draws its own menu bar at the display's top edge, so items that
/// belong to display A share A's `bounds.minY`. This is a more reliable signal
/// than horizontal position, because a hidden item on the main display sits at a
/// negative `x` and would otherwise be attributed to a display to the left.
///
/// The rules are pure so they can be covered without a window server.
public enum DisplayAttribution {
    /// Vertical tolerance when matching an item to a menu bar band.
    public static let yTolerance: Double = 2

    public static func owner(of frame: ItemFrame, among displays: [DisplayGeometry]) -> DisplayGeometry? {
        guard !displays.isEmpty else { return nil }
        let band = displays.filter { abs(frame.minY - $0.bounds.minY) <= yTolerance }
        if !band.isEmpty {
            return bestMatch(for: frame, in: band)
        }
        let intersecting = displays.filter { $0.bounds.intersects(frame) }
        if !intersecting.isEmpty {
            return bestMatch(for: frame, in: intersecting)
        }
        return displays.min { horizontalDistance($0, frame) < horizontalDistance($1, frame) }
    }

    /// True when the frame sits on the display's menu bar strip.
    ///
    /// Only the top edge is compared: status item windows are frequently taller
    /// than `NSStatusBar.thickness` (33pt windows on a 24pt bar were observed),
    /// so requiring the whole height to fit would reject valid on-screen items.
    public static func isOnScreen(_ frame: ItemFrame, display: DisplayGeometry) -> Bool {
        let inBand = abs(frame.minY - display.bounds.minY) <= yTolerance
        let inHorizontalBounds = frame.minX >= display.bounds.minX - 1
            && frame.minX < display.bounds.maxX
        return inBand && inHorizontalBounds
    }

    /// Chooses the display whose x-range contains the frame, else the closest.
    private static func bestMatch(for frame: ItemFrame, in displays: [DisplayGeometry]) -> DisplayGeometry? {
        if let containing = displays.first(where: {
            frame.minX >= $0.bounds.minX && frame.maxX <= $0.bounds.maxX
        }) {
            return containing
        }
        return displays.min { horizontalDistance($0, frame) < horizontalDistance($1, frame) }
    }

    private static func horizontalDistance(_ display: DisplayGeometry, _ frame: ItemFrame) -> Double {
        if frame.maxX < display.bounds.minX {
            return display.bounds.minX - frame.maxX
        }
        if frame.minX > display.bounds.maxX {
            return frame.minX - display.bounds.maxX
        }
        return 0
    }
}
