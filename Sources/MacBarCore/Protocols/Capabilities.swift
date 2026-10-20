import Foundation

/// Read-only capability: enumerate status items.
public protocol MenuBarScanning: Sendable {
    func scan(displayID: UInt32?) async throws -> ScanResult
    func frames(for itemIDs: [String]) async -> [String: ItemFrame]
    func displayGeometries() async -> [DisplayGeometry]
    func mainDisplay() async -> DisplayGeometry
}

/// Capability: move, click and wake status items. Implementations synthesize
/// mouse events and therefore require Accessibility permission.
public protocol MenuBarMoving: Sendable {
    func drag(itemID: String, windowID: UInt32, ownerPID: Int32, from: ItemPoint, to: ItemPoint) async throws
    func click(itemID: String, windowID: UInt32, ownerPID: Int32, at: ItemPoint, button: MouseButton) async throws
    func wakeUp(itemID: String, windowID: UInt32, ownerPID: Int32, at: ItemPoint) async throws
    /// Whether the system currently accepts synthesized events.
    func isEventPostingAvailable() -> Bool
}

public enum MouseButton: String, Sendable {
    case left
    case right
}

/// Capability: capture a status item thumbnail.
public protocol ItemCapturing: Sendable {
    func capture(windowID: UInt32, scale: Double) async -> Data?
}

/// Capability: read and request TCC permissions.
public protocol PermissionProviding: Sendable {
    func status(of kind: PermissionKind) -> PermissionStatus
    func request(_ kind: PermissionKind) -> Bool
    func openSystemSettings(for kind: PermissionKind)
}

/// Capability: persist layout, preferences, settings and audit records.
public protocol LayoutStoring: Sendable {
    func loadSnapshot() throws -> LayoutSnapshot?
    func saveSnapshot(_ snapshot: LayoutSnapshot) throws
    func loadPreferences() -> PreferencesFile
    func savePreferences(_ preferences: PreferencesFile) throws
    func loadSettings() -> AppSettings
    func saveSettings(_ settings: AppSettings) throws
    func appendLog(_ log: OperationLog)
    func loadLogs(limit: Int) -> [OperationLog]
    func exportDiagnostics() throws -> URL
    func exportDiagnostics(
        items: [MenuBarItemRecord],
        permissions: [PermissionKind: PermissionStatus],
        conflicts: [String]
    ) throws -> URL
    var storageDirectory: URL { get }
}

/// Capability: list conflicting menu bar managers.
public protocol ConflictDetecting: Sendable {
    func runningManagers() -> [String]
}

/// Capability: log in to the app at startup.
public protocol LoginItemRegistering: Sendable {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Capability: global hotkeys.
public protocol HotkeyRegistering: Sendable {
    func register(defaults: HotkeyDefaults) -> [String]
    func unregisterAll()
    func setHandler(_ handler: @escaping @Sendable (HotkeyAction) -> Void)
}

public enum HotkeyAction: String, Codable, Sendable {
    case toggleHidden
    case emergencyRestore
}

public struct HotkeyDefaults: Codable, Hashable, Sendable {
    public var toggleHidden: String
    public var emergencyRestore: String

    public init(toggleHidden: String = "⌥⌘H", emergencyRestore: String = "⌥⌘⇧R") {
        self.toggleHidden = toggleHidden
        self.emergencyRestore = emergencyRestore
    }
}

/// Clock abstraction so retries and timeouts are testable.
public protocol ClockProviding: Sendable {
    func now() -> Date
    func sleep(milliseconds: Int) async throws
}

public struct SystemClock: ClockProviding {
    public init() {}
    public func now() -> Date { Date() }
    public func sleep(milliseconds: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
    }
}
