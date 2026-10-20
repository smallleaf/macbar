import Foundation

/// A section of the macOS menu bar managed by MacBar.
///
/// Items in the ``visible`` section sit on screen. Items in ``hidden`` and
/// ``alwaysHidden`` are dragged outside the display bounds, which is the only
/// system-supported way to hide another application's status item.
public enum MenuBarSection: String, Codable, CaseIterable, Sendable, Identifiable {
    case visible
    case hidden
    case alwaysHidden

    public var id: String { rawValue }

    /// Order used when rendering sections in the panel.
    public var sortIndex: Int {
        switch self {
        case .visible: 0
        case .hidden: 1
        case .alwaysHidden: 2
        }
    }

    public var displayName: String {
        switch self {
        case .visible: "显示区"
        case .hidden: "隐藏区"
        case .alwaysHidden: "始终隐藏"
        }
    }

    public var systemImage: String {
        switch self {
        case .visible: "eye"
        case .hidden: "eye.slash"
        case .alwaysHidden: "eye.slash.circle"
        }
    }

    public var isOnScreen: Bool {
        self == .visible
    }
}
