import AppKit
import Foundation
import MacBarCore

/// Detects other menu bar managers. Two layout engines driving the same windows
/// produce a tug-of-war, so MacBar surfaces a conflict instead of fighting.
public struct AppKitConflictDetector: ConflictDetecting, @unchecked Sendable {
    public struct KnownManager: Sendable, Hashable {
        public var name: String
        public var bundleIdentifiers: [String]
        public var processNames: [String]
    }

    public static let knownManagers: [KnownManager] = [
        KnownManager(name: "Bartender", bundleIdentifiers: ["com.surteesstudios.Bartender"], processNames: ["Bartender"]),
        KnownManager(name: "Ice", bundleIdentifiers: ["com.jordanbaird.Ice"], processNames: ["Ice"]),
        KnownManager(name: "Thaw", bundleIdentifiers: [], processNames: ["Thaw"]),
        KnownManager(name: "Barbee", bundleIdentifiers: [], processNames: ["Barbee"]),
        KnownManager(name: "Hidden Bar", bundleIdentifiers: ["com.dwarvesv.minimalbar"], processNames: ["Hidden Bar"]),
        KnownManager(name: "Dozer", bundleIdentifiers: ["com.mortennn.Dozer"], processNames: ["Dozer"]),
    ]

    private let processLister: @Sendable () -> [String]

    public init(processLister: @escaping @Sendable () -> [String] = AppKitConflictDetector.listProcesses) {
        self.processLister = processLister
    }

    public func runningManagers() -> [String] {
        var found = Set<String>()
        let apps = NSWorkspace.shared.runningApplications
        let processes = processLister()
        for manager in Self.knownManagers {
            let appHit = apps.contains { app in
                if let bundle = app.bundleIdentifier, manager.bundleIdentifiers.contains(bundle) {
                    return true
                }
                if let name = app.localizedName, manager.processNames.contains(name) {
                    return true
                }
                return false
            }
            let processHit = processes.contains { path in
                manager.processNames.contains { path.hasSuffix("/\($0)") || path == $0 }
            }
            if appHit || processHit {
                found.insert(manager.name)
            }
        }
        return found.sorted()
    }

    /// Lists running executable paths via `sysctl`.
    ///
    /// Spawning `ps` blocks the calling thread until the child exits, and doing
    /// that on the main actor deadlocked the app during launch (observed on
    /// macOS 26.2: `waitUntilExit` sat in a nested run loop indefinitely).
    /// `KERN_PROC_ALL` reads the same information without a subprocess.
    public static func listProcesses() -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var size = 0
        guard sysctl(&mib, 4, nil, &size, nil, 0) == 0, size > 0 else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 4, &buffer, &size, nil, 0) == 0 else { return [] }
        let count = size / MemoryLayout<kinfo_proc>.stride
        return buffer.withUnsafeBytes { raw -> [String] in
            let processes = raw.bindMemory(to: kinfo_proc.self)
            return (0..<count).compactMap { index in
                var info = processes[index]
                let path = withUnsafeBytes(of: &info.kp_proc.p_comm) { commBytes -> String in
                    let chars = commBytes.map { Int8(bitPattern: $0) }
                    let truncated = chars.prefix { $0 != 0 }
                    return String(decoding: truncated.map { UInt8(bitPattern: $0) }, as: UTF8.self)
                }
                return path.isEmpty ? nil : path
            }
        }
    }
}
