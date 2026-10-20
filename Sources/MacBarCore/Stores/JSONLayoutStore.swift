import Foundation

/// File-backed persistence for snapshots, preferences, settings and audit logs.
///
/// Files live in `~/Library/Application Support/MacBar`. Writes go through a
/// temporary file followed by an atomic replace, so a crash never leaves a
/// half-written snapshot. A corrupt file is renamed instead of deleted, which
/// keeps it available for diagnostics.
public final class JSONLayoutStore: LayoutStoring, @unchecked Sendable {
    public let storageDirectory: URL
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "com.miyuan.macbar.store", qos: .utility)
    private let encoder: JSONEncoder
    private let lineEncoder: JSONEncoder
    private let decoder: JSONDecoder
    private let dateFormatter: ISO8601DateFormatter

    public struct Paths {
        public var snapshot: URL
        public var preferences: URL
        public var settings: URL
        public var logs: URL
        public var icons: URL

        public init(directory: URL) {
            snapshot = directory.appendingPathComponent("layout.json")
            preferences = directory.appendingPathComponent("preferences.json")
            settings = directory.appendingPathComponent("settings.json")
            logs = directory.appendingPathComponent("operations.jsonl")
            icons = directory.appendingPathComponent("icons", isDirectory: true)
        }
    }

    public let paths: Paths

    public init(directory: URL? = nil, fileManager: FileManager = .default) {
        let resolved = directory ?? Self.defaultDirectory(fileManager: fileManager)
        self.storageDirectory = resolved
        self.fileManager = fileManager
        self.paths = Paths(directory: resolved)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let lineEncoder = JSONEncoder()
        lineEncoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        lineEncoder.dateEncodingStrategy = .iso8601
        self.lineEncoder = lineEncoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
        self.dateFormatter = ISO8601DateFormatter()
        try? fileManager.createDirectory(at: resolved, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: paths.icons, withIntermediateDirectories: true)
    }

    public static func defaultDirectory(fileManager: FileManager = .default) -> URL {
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return base.appendingPathComponent("MacBar", isDirectory: true)
    }

    // MARK: - Snapshot

    public func loadSnapshot() throws -> LayoutSnapshot? {
        try queue.sync {
            guard fileManager.fileExists(atPath: paths.snapshot.path) else { return nil }
            do {
                let data = try Data(contentsOf: paths.snapshot)
                var snapshot = try decoder.decode(LayoutSnapshot.self, from: data)
                if snapshot.schemaVersion > LayoutSnapshot.currentSchemaVersion {
                    MacBarLog.warning(.store, "snapshot schema is newer than app schema=\(snapshot.schemaVersion)")
                }
                snapshot.schemaVersion = LayoutSnapshot.currentSchemaVersion
                return snapshot
            } catch {
                try? quarantine(paths.snapshot)
                MacBarLog.warning(.store, "snapshot unreadable moved to quarantine code=\(MacBarError.storeReadFailed(error.localizedDescription).code)")
                return nil
            }
        }
    }

    public func saveSnapshot(_ snapshot: LayoutSnapshot) throws {
        try queue.sync {
            try write(snapshot, to: paths.snapshot)
        }
    }

    // MARK: - Preferences

    public func loadPreferences() -> PreferencesFile {
        queue.sync {
            guard let data = try? Data(contentsOf: paths.preferences) else { return PreferencesFile() }
            do {
                return try decoder.decode(PreferencesFile.self, from: data)
            } catch {
                try? quarantine(paths.preferences)
                MacBarLog.warning(.store, "preferences unreadable moved to quarantine")
                return PreferencesFile()
            }
        }
    }

    public func savePreferences(_ preferences: PreferencesFile) throws {
        try queue.sync {
            try write(preferences, to: paths.preferences)
        }
    }

    // MARK: - Settings

    public func loadSettings() -> AppSettings {
        queue.sync {
            guard let data = try? Data(contentsOf: paths.settings) else { return .default }
            do {
                return try decoder.decode(AppSettings.self, from: data)
            } catch {
                try? quarantine(paths.settings)
                MacBarLog.warning(.store, "settings unreadable moved to quarantine")
                return .default
            }
        }
    }

    public func saveSettings(_ settings: AppSettings) throws {
        try queue.sync {
            try write(settings, to: paths.settings)
        }
    }

    // MARK: - Logs

    public func appendLog(_ log: OperationLog) {
        let paths = self.paths
        let encoder = self.lineEncoder
        let fileManager = self.fileManager
        queue.async {
            guard var data = try? encoder.encode(log) else { return }
            data.append(0x0A)
            if !fileManager.fileExists(atPath: paths.logs.path) {
                fileManager.createFile(atPath: paths.logs.path, contents: data)
                return
            }
            guard let handle = try? FileHandle(forWritingTo: paths.logs) else { return }
            defer { try? handle.close() }
            do {
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
            } catch {
                MacBarLog.warning(.store, "append audit log failed")
            }
        }
    }

    public func loadLogs(limit: Int) -> [OperationLog] {
        queue.sync {
            guard let data = try? Data(contentsOf: paths.logs),
                  let text = String(data: data, encoding: .utf8) else {
                return []
            }
            let lines = text.split(separator: "\n").suffix(max(0, limit))
            return lines.compactMap { line in
                guard let lineData = line.data(using: .utf8) else { return nil }
                return try? decoder.decode(OperationLog.self, from: lineData)
            }
        }
    }

    /// Rotates the audit log, keeping at most `maxBytes`.
    public func rotateLogs(maxBytes: Int = 512 * 1024) {
        let paths = self.paths
        let fileManager = self.fileManager
        queue.async {
            guard let attributes = try? fileManager.attributesOfItem(atPath: paths.logs.path),
                  let size = attributes[.size] as? Int,
                  size > maxBytes,
                  let data = try? Data(contentsOf: paths.logs) else {
                return
            }
            let keep = data.suffix(maxBytes / 2)
            if let newlineIndex = keep.firstIndex(of: 0x0A) {
                let trimmed = keep.suffix(from: keep.index(after: newlineIndex))
                try? Data(trimmed).write(to: paths.logs, options: .atomic)
            }
        }
    }

    // MARK: - Diagnostics

    public func exportDiagnostics() throws -> URL {
        let report = DiagnosticsReport(
            generatedAt: Date(),
            appVersion: MacBarVersion.current,
            build: MacBarVersion.build,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: DiagnosticsReport.hardwareModel(),
            storageDirectory: storageDirectory.path,
            settings: loadSettings(),
            preferences: loadPreferences(),
            snapshot: try? loadSnapshot(),
            logs: loadLogs(limit: 300),
            items: []
        )
        let url = storageDirectory.appendingPathComponent("diagnostics-\(Int(Date().timeIntervalSince1970)).txt")
        try report.render().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Diagnostics including a live item list supplied by the caller.
    public func exportDiagnostics(items: [MenuBarItemRecord], permissions: [PermissionKind: PermissionStatus], conflicts: [String]) throws -> URL {
        let report = DiagnosticsReport(
            generatedAt: Date(),
            appVersion: MacBarVersion.current,
            build: MacBarVersion.build,
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            model: DiagnosticsReport.hardwareModel(),
            storageDirectory: storageDirectory.path,
            settings: loadSettings(),
            preferences: loadPreferences(),
            snapshot: try? loadSnapshot(),
            logs: loadLogs(limit: 300),
            items: items,
            permissions: permissions,
            conflicts: conflicts
        )
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let url = storageDirectory.appendingPathComponent("diagnostics-\(formatter.string(from: Date())).txt")
        try report.render().write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    // MARK: - Helpers

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        do {
            let data = try encoder.encode(value)
            let temporary = url.deletingLastPathComponent()
                .appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
            try data.write(to: temporary, options: .atomic)
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporary)
            } else {
                try fileManager.moveItem(at: temporary, to: url)
            }
        } catch {
            MacBarLog.warning(.store, "write failed file=\(url.lastPathComponent) code=\(MacBarError.storeWriteFailed(error.localizedDescription).code)")
            throw MacBarError.storeWriteFailed(error.localizedDescription)
        }
    }

    private func quarantine(_ url: URL) throws {
        guard fileManager.fileExists(atPath: url.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        let target = url.deletingLastPathComponent()
            .appendingPathComponent("\(url.lastPathComponent).corrupt-\(stamp)")
        try? fileManager.moveItem(at: url, to: target)
    }
}

/// A plain-text snapshot of the environment used for support requests.
public struct DiagnosticsReport: Sendable {
    public var generatedAt: Date
    public var appVersion: String
    public var build: String
    public var osVersion: String
    public var model: String
    public var storageDirectory: String
    public var settings: AppSettings
    public var preferences: PreferencesFile
    public var snapshot: LayoutSnapshot?
    public var logs: [OperationLog]
    public var items: [MenuBarItemRecord]
    public var permissions: [PermissionKind: PermissionStatus]
    public var conflicts: [String]

    public init(
        generatedAt: Date,
        appVersion: String,
        build: String,
        osVersion: String,
        model: String,
        storageDirectory: String,
        settings: AppSettings,
        preferences: PreferencesFile,
        snapshot: LayoutSnapshot?,
        logs: [OperationLog],
        items: [MenuBarItemRecord],
        permissions: [PermissionKind: PermissionStatus] = [:],
        conflicts: [String] = []
    ) {
        self.generatedAt = generatedAt
        self.appVersion = appVersion
        self.build = build
        self.osVersion = osVersion
        self.model = model
        self.storageDirectory = storageDirectory
        self.settings = settings
        self.preferences = preferences
        self.snapshot = snapshot
        self.logs = logs
        self.items = items
        self.permissions = permissions
        self.conflicts = conflicts
    }

    public static func hardwareModel() -> String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        guard size > 0 else { return "unknown" }
        var buffer = [CChar](repeating: 0, count: size)
        sysctlbyname("hw.model", &buffer, &size, nil, 0)
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    public func render() -> String {
        let formatter = ISO8601DateFormatter()
        var lines: [String] = []
        lines.append("MacBar Diagnostics")
        lines.append("generatedAt: \(formatter.string(from: generatedAt))")
        lines.append("appVersion: \(appVersion) (\(build))")
        lines.append("osVersion: \(osVersion)")
        lines.append("model: \(model)")
        lines.append("storage: \(storageDirectory)")
        lines.append("")
        lines.append("[Permissions]")
        if permissions.isEmpty {
            lines.append("  (not collected)")
        } else {
            for kind in PermissionKind.allCases {
                lines.append("  \(kind.rawValue): \(permissions[kind]?.rawValue ?? "unknown")")
            }
        }
        lines.append("")
        lines.append("[Conflicts]")
        lines.append(conflicts.isEmpty ? "  none" : conflicts.map { "  \($0)" }.joined(separator: "\n"))
        lines.append("")
        lines.append("[Settings]")
        lines.append("  launchAtLogin: \(settings.launchAtLogin)")
        lines.append("  restoreOnQuit: \(settings.restoreOnQuit)")
        lines.append("  manageAllDisplays: \(settings.manageAllDisplays)")
        lines.append("  captureIcons: \(settings.captureIcons)")
        lines.append("  conflictPolicy: \(settings.conflictPolicy.rawValue)")
        lines.append("")
        lines.append("[Items]")
        if items.isEmpty {
            lines.append("  (not collected)")
        } else {
            for item in items {
                lines.append(
                    "  \(item.id) | section=\(item.section.rawValue) | frame=(\(Int(item.frame.x)),\(Int(item.frame.y)),\(Int(item.frame.width)),\(Int(item.frame.height))) | movable=\(item.isMovable) | hideable=\(item.isHideable)"
                )
            }
        }
        lines.append("")
        lines.append("[Snapshot]")
        if let snapshot {
            lines.append("  display=\(snapshot.displayID) width=\(Int(snapshot.screenWidth)) height=\(Int(snapshot.menuBarHeight))")
            for section in MenuBarSection.allCases {
                lines.append("  \(section.rawValue): \(snapshot.items(in: section).joined(separator: ", "))")
            }
        } else {
            lines.append("  none")
        }
        lines.append("")
        lines.append("[Recent Operations]")
        for log in logs.reversed() {
            lines.append(
                "  \(formatter.string(from: log.startedAt)) \(log.opType.rawValue) \(log.itemID ?? "-") \(log.result.rawValue) code=\(log.errorCode ?? "-") retries=\(log.retryCount) duration=\(log.durationMs)ms"
            )
        }
        return lines.joined(separator: "\n")
    }
}
