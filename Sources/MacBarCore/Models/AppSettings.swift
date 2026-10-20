import Foundation

/// Policy applied when another menu bar manager is running.
public enum ConflictPolicy: String, Codable, CaseIterable, Sendable {
    /// Show a banner but allow operations.
    case warn
    /// Block every moving operation and stay read-only.
    case block

    public var displayName: String {
        switch self {
        case .warn: "提示但允许操作"
        case .block: "阻止操作"
        }
    }
}

/// User-configurable application settings.
public struct AppSettings: Codable, Hashable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var launchAtLogin: Bool
    public var showDockIcon: Bool
    public var revealOnHover: Bool
    public var autoRehideDelayMs: Int
    public var hotkeyToggleHidden: String
    public var hotkeyEmergencyRestore: String
    public var restoreOnQuit: Bool
    public var manageAllDisplays: Bool
    public var captureIcons: Bool
    public var showSystemItemsInPanel: Bool
    public var conflictPolicy: ConflictPolicy
    public var language: String
    public var consentVersion: Int
    public var showControlItem: Bool
    /// Signature fingerprint of the build that was last seen running. A change
    /// means the app was rebuilt; with ad-hoc signing this invalidates the
    /// Accessibility grant stored by the system.
    public var lastSignatureFingerprint: String
    /// Set once the user has been shown how to allow MacBar in the macOS 26
    /// "Menu Bar" pane. Prevents repeating the same alert on every launch.
    public var hasShownMenuBarAllowListGuidance: Bool

    public init(
        schemaVersion: Int = AppSettings.currentSchemaVersion,
        launchAtLogin: Bool = false,
        showDockIcon: Bool = false,
        revealOnHover: Bool = false,
        autoRehideDelayMs: Int = 5_000,
        hotkeyToggleHidden: String = "⌥⌘H",
        hotkeyEmergencyRestore: String = "⌥⌘⇧R",
        restoreOnQuit: Bool = false,
        manageAllDisplays: Bool = false,
        captureIcons: Bool = true,
        showSystemItemsInPanel: Bool = true,
        conflictPolicy: ConflictPolicy = .warn,
        language: String = "zh-Hans",
        consentVersion: Int = 0,
        showControlItem: Bool = true,
        lastSignatureFingerprint: String = "",
        hasShownMenuBarAllowListGuidance: Bool = false
    ) {
        self.schemaVersion = schemaVersion
        self.launchAtLogin = launchAtLogin
        self.showDockIcon = showDockIcon
        self.revealOnHover = revealOnHover
        self.autoRehideDelayMs = autoRehideDelayMs
        self.hotkeyToggleHidden = hotkeyToggleHidden
        self.hotkeyEmergencyRestore = hotkeyEmergencyRestore
        self.restoreOnQuit = restoreOnQuit
        self.manageAllDisplays = manageAllDisplays
        self.captureIcons = captureIcons
        self.showSystemItemsInPanel = showSystemItemsInPanel
        self.conflictPolicy = conflictPolicy
        self.language = language
        self.consentVersion = consentVersion
        self.showControlItem = showControlItem
        self.lastSignatureFingerprint = lastSignatureFingerprint
        self.hasShownMenuBarAllowListGuidance = hasShownMenuBarAllowListGuidance
    }

    /// True once the user completed the onboarding flow.
    public var hasCompletedOnboarding: Bool { consentVersion > 0 }

    public static let `default` = AppSettings()
}

/// Version metadata injected by the build script. Falls back to a development
/// value when running from a Swift package build.
public enum MacBarVersion {
    public static var current: String {
        if let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String,
           !version.isEmpty {
            return version
        }
        return "1.0.0-dev"
    }

    public static var build: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String) ?? "0"
    }

    public static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? "com.miyuan.macbar"
    }
}
