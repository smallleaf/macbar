import AppKit
import Foundation
import MacBarCore

/// Global shortcuts backed by `NSEvent` monitors.
///
/// A global monitor only observes key presses, so it needs Accessibility trust
/// (which MacBar already requires) and never swallows events owned by other
/// applications. Secure Input fields are intentionally not intercepted.
public final class GlobalHotkeyService: HotkeyRegistering, @unchecked Sendable {
    public struct Combo: Sendable, Equatable {
        public var flags: NSEvent.ModifierFlags
        public var key: String

        public init(flags: NSEvent.ModifierFlags, key: String) {
            self.flags = flags
            self.key = key
        }

        /// Parses strings such as `⌥⌘H` or `ctrl+shift+r`.
        public init?(_ raw: String) {
            var flags: NSEvent.ModifierFlags = []
            var key: String?
            for character in raw {
                switch character {
                case "⌃": flags.insert(.control)
                case "⌥": flags.insert(.option)
                case "⌘": flags.insert(.command)
                case "⇧": flags.insert(.shift)
                case " ", "+": continue
                default:
                    if key != nil { return nil }
                    key = String(character).uppercased()
                }
            }
            let lowered = raw.lowercased()
            if lowered.contains("ctrl") || lowered.contains("control") { flags.insert(.control) }
            if lowered.contains("alt") || lowered.contains("option") { flags.insert(.option) }
            if lowered.contains("cmd") || lowered.contains("command") { flags.insert(.command) }
            if lowered.contains("shift") { flags.insert(.shift) }
            if key == nil, let last = raw.last, !"⌃⌥⌘⇧+ ".contains(last) {
                key = String(last).uppercased()
            }
            guard let key, !key.isEmpty else { return nil }
            self.init(flags: flags, key: key)
        }

        public var displayString: String {
            var result = ""
            if flags.contains(.control) { result += "⌃" }
            if flags.contains(.option) { result += "⌥" }
            if flags.contains(.shift) { result += "⇧" }
            if flags.contains(.command) { result += "⌘" }
            return result + key
        }
    }

    private let lock = NSLock()
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var bindings: [(combo: Combo, action: HotkeyAction)] = []
    private var handler: (@Sendable (HotkeyAction) -> Void)?

    public init() {}

    @discardableResult
    public func register(defaults: HotkeyDefaults) -> [String] {
        unregisterAll()
        var invalid: [String] = []
        var registered: [(Combo, HotkeyAction)] = []
        if let combo = Combo(defaults.toggleHidden) {
            registered.append((combo, .toggleHidden))
        } else {
            invalid.append(defaults.toggleHidden)
        }
        if let combo = Combo(defaults.emergencyRestore) {
            registered.append((combo, .emergencyRestore))
        } else {
            invalid.append(defaults.emergencyRestore)
        }
        lock.lock()
        bindings = registered
        lock.unlock()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event)
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if self.handle(event) {
                return nil
            }
            return event
        }
        if !invalid.isEmpty {
            MacBarLog.warning(.hotkey, "invalid hotkey specifications count=\(invalid.count)")
        }
        return invalid
    }

    public func unregisterAll() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
        globalMonitor = nil
        localMonitor = nil
        lock.lock()
        bindings = []
        lock.unlock()
    }

    public func setHandler(_ handler: @escaping @Sendable (HotkeyAction) -> Void) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    /// Returns true when the event matched a binding.
    @discardableResult
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.control, .option, .shift, .command])
        guard let key = event.charactersIgnoringModifiers?.uppercased(), !key.isEmpty else { return false }
        lock.lock()
        let binding = bindings.first { $0.combo.flags == flags && $0.combo.key == key }
        let handler = self.handler
        lock.unlock()
        guard let binding else { return false }
        MacBarLog.info(.hotkey, "hotkey triggered action=\(binding.action.rawValue)")
        handler?(binding.action)
        return true
    }

    deinit {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
        }
    }
}
