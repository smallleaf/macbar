import Foundation

/// Lifecycle of a single item move, driven by ``LayoutCoordinator``.
///
/// ```text
/// idle ──start──▶ moving ──success──▶ succeeded
///                    │
///                    ├─retry──▶ moving
///                    │
///                    └─failure──▶ failed ──rollback──▶ rolledBack
/// ```
public enum MoveState: String, Codable, Sendable {
    case idle
    case moving
    case succeeded
    case failed
    case rolledBack

    public var isTerminal: Bool {
        switch self {
        case .idle, .moving: false
        case .succeeded, .failed, .rolledBack: true
        }
    }
}

/// Events accepted by the move state machine.
public enum MoveEvent: Sendable, Equatable {
    case start
    case retry
    case success
    case failure
    case rollback
    case giveUp
}

/// A deterministic move state machine. Kept separate from the coordinator so
/// transitions can be covered by unit tests without touching the window server.
public struct MoveMachine: Sendable, Equatable {
    public private(set) var state: MoveState = .idle

    public init(state: MoveState = .idle) {
        self.state = state
    }

    /// Applies an event and returns the resulting state. Invalid transitions are
    /// ignored (the state machine is total: it never throws).
    @discardableResult
    public mutating func apply(_ event: MoveEvent) -> MoveState {
        state = MoveMachine.next(from: state, event: event)
        return state
    }

    public static func next(from state: MoveState, event: MoveEvent) -> MoveState {
        switch (state, event) {
        case (.idle, .start): .moving
        case (.moving, .success): .succeeded
        case (.moving, .retry): .moving
        case (.moving, .failure): .failed
        case (.moving, .rollback): .rolledBack
        case (.failed, .rollback): .rolledBack
        case (.failed, .start): .moving
        case (.rolledBack, .start): .moving
        case (.succeeded, .start): .moving
        case (.moving, .giveUp), (.idle, .giveUp): .rolledBack
        default: state
        }
    }
}

/// High-level application availability.
public enum AppMode: String, Codable, Sendable {
    /// Full control: permissions granted and no conflicting tool.
    case ready
    /// Read-only: missing permissions, conflict, or a compatibility problem.
    case degraded
    /// First launch flow has not been completed yet.
    case onboarding

    public var canOperate: Bool { self == .ready }

    public var displayName: String {
        switch self {
        case .ready: "可管理"
        case .degraded: "只读模式"
        case .onboarding: "待引导"
        }
    }
}

/// Lifecycle state machine of the application shell.
public struct AppLifecycleMachine: Sendable, Equatable {
    public private(set) var mode: AppMode

    public init(mode: AppMode = .onboarding) {
        self.mode = mode
    }

    public mutating func setOnboardingCompleted(permissionGranted: Bool) {
        mode = permissionGranted ? .ready : .degraded
    }

    public mutating func degrade() {
        mode = .degraded
    }

    public mutating func recover() {
        mode = .ready
    }
}

/// Coarse permission states.
public enum PermissionStatus: String, Codable, Sendable {
    case unknown
    case granted
    case denied
    case restricted

    public var isGranted: Bool { self == .granted }
}

public enum PermissionKind: String, Codable, CaseIterable, Sendable, Identifiable {
    case accessibility
    case screenRecording

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .accessibility: "辅助功能"
        case .screenRecording: "屏幕录制"
        }
    }

    public var isRequired: Bool {
        self == .accessibility
    }

    public var explanation: String {
        switch self {
        case .accessibility:
            "移动其他应用的菜单栏图标需要模拟拖拽，这是 macOS 唯一可行的方式。MacBar 只在本机使用该权限。"
        case .screenRecording:
            "用于截取菜单栏图标的真实缩略图。未授权时将以应用图标代替，不影响隐藏/显示功能。"
        }
    }
}
