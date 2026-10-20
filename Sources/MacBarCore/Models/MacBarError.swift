import Foundation

/// Typed errors with stable codes. Codes are logged in diagnostics exports and
/// mapped to user-facing copy by the UI layer.
public enum MacBarError: Error, Hashable, Sendable, LocalizedError {
    case accessibilityDenied
    case itemNotMovable(itemID: String)
    case moveTimedOut(itemID: String)
    case eventCreationFailed
    case screenCaptureDenied
    case conflictDetected(apps: [String])
    case itemDisappeared(itemID: String)
    case layoutVerificationFailed(itemID: String)
    case storeReadFailed(String)
    case storeWriteFailed(String)
    case compatibilityIssue(reason: String)
    case notAvailableOnThisSystem
    case cancelled
    case unknown(String)

    public var code: String {
        switch self {
        case .accessibilityDenied: "MB-E1001"
        case .itemNotMovable: "MB-E1002"
        case .moveTimedOut: "MB-E1003"
        case .eventCreationFailed: "MB-E1004"
        case .screenCaptureDenied: "MB-E1005"
        case .conflictDetected: "MB-E1006"
        case .itemDisappeared: "MB-E1007"
        case .layoutVerificationFailed: "MB-E1008"
        case .storeReadFailed: "MB-E1009"
        case .storeWriteFailed: "MB-E1009"
        case .compatibilityIssue: "MB-E1010"
        case .notAvailableOnThisSystem: "MB-E2001"
        case .cancelled: "MB-E2002"
        case .unknown: "MB-E9999"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .accessibilityDenied:
            "需要「辅助功能」权限才能移动菜单栏图标"
        case .itemNotMovable:
            "系统不允许移动此图标"
        case .moveTimedOut:
            "移动未生效，已尝试恢复原状"
        case .eventCreationFailed:
            "系统拒绝了操作，请重启 MacBar 后重试"
        case .screenCaptureDenied:
            "未授权屏幕录制，图标将以应用图标显示"
        case .conflictDetected(let apps):
            "检测到同类工具正在运行：\(apps.joined(separator: "、"))"
        case .itemDisappeared:
            "该图标已消失，对应应用可能已退出"
        case .layoutVerificationFailed:
            "布局未完全生效"
        case .storeReadFailed(let detail):
            "读取布局数据失败：\(detail)"
        case .storeWriteFailed(let detail):
            "保存布局数据失败：\(detail)"
        case .compatibilityIssue(let reason):
            "系统菜单栏状态异常：\(reason)"
        case .notAvailableOnThisSystem:
            "当前系统不支持该能力"
        case .cancelled:
            "操作已取消"
        case .unknown(let detail):
            detail.isEmpty ? "未知错误" : detail
        }
    }

    /// Whether a batch operation should stop when this error occurs.
    public var isFatalForBatch: Bool {
        switch self {
        case .accessibilityDenied, .conflictDetected, .compatibilityIssue, .notAvailableOnThisSystem:
            true
        case .itemNotMovable, .itemDisappeared:
            false
        case .cancelled:
            true
        default:
            false
        }
    }

    /// Suggested recovery hint shown in the UI.
    public var recoverySuggestion: String? {
        switch self {
        case .accessibilityDenied:
            "在「系统设置 → 隐私与安全性 → 辅助功能」中勾选 MacBar"
        case .conflictDetected:
            "请先退出其他菜单栏管理工具，或将其设为只读"
        case .compatibilityIssue:
            "请在「系统设置 → 菜单栏」中检查本应用的显示开关，或导出诊断信息"
        case .storeWriteFailed:
            "请检查磁盘空间与文件权限"
        default:
            nil
        }
    }
}
