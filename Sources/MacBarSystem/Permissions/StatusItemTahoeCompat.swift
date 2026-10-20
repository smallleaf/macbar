import Foundation
import MacBarCore

/// Detects the menu bar anomalies introduced by macOS 26 (Tahoe).
///
/// Tahoe routes every status item through Control Center's layout engine. Two
/// failures have been observed in the wild: an application's own status item is
/// positioned off screen (`y = -17`), and third-party items are assigned no
/// position at all. Neither can be repaired programmatically when the system
/// setting for the app is disabled, so this inspector produces findings that the
/// UI turns into guidance.
public struct StatusItemTahoeCompat: Sendable {
    public enum Severity: String, Sendable {
        case info
        case warning
        case critical
    }

    public struct Finding: Sendable, Hashable, Identifiable {
        public var id: String { code + message }
        public var severity: Severity
        public var code: String
        public var message: String
        public var recoverySuggestion: String?
    }

    public init() {}

    public var isTahoeOrLater: Bool {
        ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        )
    }

    public func inspect(
        items: [MenuBarItemRecord],
        display: DisplayGeometry,
        ownItemFrames: [ItemFrame],
        ownItemVisible: Bool
    ) -> [Finding] {
        var findings: [Finding] = []

        if !ownItemVisible {
            findings.append(
                Finding(
                    severity: .critical,
                    code: MacBarError.compatibilityIssue(reason: "control item missing").code,
                    message: "MacBar 的控制图标未出现在菜单栏",
                    recoverySuggestion: "请在「系统设置 → 菜单栏」中确认 MacBar 未被隐藏"
                )
            )
        }

        let abnormalOwnFrames = ownItemFrames.filter { $0.minY < display.bounds.minY - 1 }
        if !abnormalOwnFrames.isEmpty {
            findings.append(
                Finding(
                    severity: .critical,
                    code: MacBarError.compatibilityIssue(reason: "own item offscreen").code,
                    message: "系统将 MacBar 的控制图标移到了屏幕外",
                    recoverySuggestion: "请重启 MacBar；若持续出现，请在「系统设置 → 菜单栏」中检查该应用"
                )
            )
        }

        let visibleButOffscreen = items.filter { $0.section == .visible && $0.frame.minY < display.bounds.minY - 1 }
        if !visibleButOffscreen.isEmpty && isTahoeOrLater {
            findings.append(
                Finding(
                    severity: .warning,
                    code: MacBarError.compatibilityIssue(reason: "visible item offscreen").code,
                    message: "\(visibleButOffscreen.count) 个图标被系统布局到屏幕外",
                    recoverySuggestion: "可尝试「重置布局」；若无效请导出诊断信息"
                )
            )
        }

        if isTahoeOrLater {
            findings.append(
                Finding(
                    severity: .info,
                    code: "MB-I3001",
                    message: "当前系统由「控制中心」统一管理菜单栏布局（macOS 26+）",
                    recoverySuggestion: nil
                )
            )
        }
        return findings
    }

    /// True when the item frame sits outside the menu bar band of its display.
    public func isFrameAnomalous(_ frame: ItemFrame, display: DisplayGeometry) -> Bool {
        frame.minY < display.bounds.minY - 1 || frame.minY > display.bounds.minY + display.menuBarHeight + 8
    }
}
