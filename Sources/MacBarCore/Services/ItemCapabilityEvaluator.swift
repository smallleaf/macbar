import Foundation

/// Decides which status items may be moved or hidden.
///
/// macOS reserves a handful of items: the clock, Siri, Control Center and the
/// system indicators that appear while audio or the screen is being recorded.
/// Attempting to move them either fails or produces a broken layout, so they are
/// rejected before any event is synthesized.
public struct ItemCapabilityEvaluator: Sendable {
    public struct Rule: Sendable, Equatable {
        public var bundleIdentifier: String
        public var title: String
        public var isMovable: Bool
        public var isHideable: Bool
    }

    /// Items that must never be moved.
    public static let immovableRules: [Rule] = [
        Rule(bundleIdentifier: "com.apple.controlcenter", title: "Clock", isMovable: false, isHideable: false),
        Rule(bundleIdentifier: "com.apple.systemuiserver", title: "Siri", isMovable: false, isHideable: false),
        Rule(bundleIdentifier: "com.apple.controlcenter", title: "BentoBox", isMovable: false, isHideable: false),
        Rule(bundleIdentifier: "com.apple.controlcenter", title: "AudioVideoModule", isMovable: false, isHideable: false),
        Rule(bundleIdentifier: "com.apple.controlcenter", title: "FaceTime", isMovable: false, isHideable: false),
        Rule(bundleIdentifier: "com.apple.controlcenter", title: "MusicRecognition", isMovable: false, isHideable: false),
        Rule(bundleIdentifier: "com.apple.WindowManager", title: "", isMovable: false, isHideable: false),
    ]

    /// Items macOS technically allows to move but users expect to keep.
    public static let nonHideableTitles: Set<String> = [
        "Clock",
        "Siri",
        "BentoBox",
        "AudioVideoModule",
        "FaceTime",
        "MusicRecognition",
        "ScreenCaptureUI",
        "ControlCenter",
        "MenuBarExtra",
        "NotificationCenter",
        "Spotlight",
        "MacBar",
    ]

    /// Bundle identifiers that always belong to the system.
    public static let systemBundleIdentifiers: Set<String> = [
        "com.apple.controlcenter",
        "com.apple.systemuiserver",
        "com.apple.notificationcenterui",
        "com.apple.WindowManager",
        "com.apple.Spotlight",
        "com.apple.ScreenCaptureUI",
    ]

    public init() {}

    public func isSystemOwned(bundleIdentifier: String?, ownerName: String) -> Bool {
        if let bundleIdentifier, Self.systemBundleIdentifiers.contains(bundleIdentifier) {
            return true
        }
        if Self.systemBundleIdentifiers.contains(ownerName) {
            return true
        }
        return false
    }

    public func canMove(bundleIdentifier: String?, title: String) -> Bool {
        if let rule = Self.immovableRules.first(where: { rule in
            guard let bundleIdentifier else { return false }
            return rule.bundleIdentifier == bundleIdentifier && rule.title == title
        }) {
            return rule.isMovable
        }
        return true
    }

    public func canHide(bundleIdentifier: String?, title: String) -> Bool {
        if let rule = Self.immovableRules.first(where: { rule in
            guard let bundleIdentifier else { return false }
            return rule.bundleIdentifier == bundleIdentifier && rule.title == title
        }) {
            return rule.isHideable
        }
        if Self.nonHideableTitles.contains(title) {
            return false
        }
        return true
    }

    /// Reason text displayed in the panel for a disabled item.
    public func disabledReason(bundleIdentifier: String?, title: String) -> String? {
        if !canHide(bundleIdentifier: bundleIdentifier, title: title) {
            return "系统保留图标，无法隐藏"
        }
        if !canMove(bundleIdentifier: bundleIdentifier, title: title) {
            return "系统不允许移动此图标"
        }
        return nil
    }
}
