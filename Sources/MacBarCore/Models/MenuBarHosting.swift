import Foundation

/// Whether macOS is hosting MacBar's status item.
///
/// Since macOS 26 the menu bar is rendered by Control Center. An application's
/// status item becomes a "host" there and only gets a layer-25 window once
/// Control Center decides to show it. When the app is disabled in
/// `System Settings > Menu Bar` (or caught by a stale entry that maps its item
/// to a different, disabled app) Control Center keeps receiving the item but
/// never surfaces a window. `NSStatusItem` still reports a valid button frame in
/// that state, so the only trustworthy signal is the window server.
public enum MenuBarHosting {
    public enum Status: String, Sendable, Codable {
        /// A layer-25 window owned by this process exists.
        case hosted
        /// No layer-25 window; the system is not showing the item.
        case notHosted
        /// Not enough information yet (first moments after launch).
        case unknown

        public var isFailure: Bool { self == .notHosted }
    }

    /// Number of consecutive checks before reporting `notHosted`. Control Center
    /// registers a new item asynchronously, so a short grace period avoids false
    /// alarms on every launch.
    public static let maxMisses = 6
    /// Interval between checks, in seconds.
    public static let pollInterval = 1.0

    /// Pure decision function so the timing rules can be tested.
    public static func status(misses: Int, sawHostedWindow: Bool) -> Status {
        if sawHostedWindow { return .hosted }
        return misses >= maxMisses ? .notHosted : .unknown
    }
}
