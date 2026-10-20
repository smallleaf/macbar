import CoreGraphics
import Foundation
import MacBarCore

/// Watches the window server to confirm that macOS is actually rendering
/// MacBar's status item.
public struct StatusItemHostChecker: Sendable {
    public init() {}

    /// True when this process owns at least one layer-25 window.
    public func hasHostedStatusItem() -> Bool {
        let pid = Int32(ProcessInfo.processInfo.processIdentifier)
        let level = Int(CGWindowLevelForKey(.statusWindow))
        guard let list = CGWindowListCopyWindowInfo([.optionAll, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return false
        }
        return list.contains { info in
            let owner = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? -1
            let layer = (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? -1
            return owner == pid && layer == level
        }
    }

    /// Polls until the item is hosted or the grace period elapses.
    public func waitForHosting(
        timeout: TimeInterval = MenuBarHosting.pollInterval * Double(MenuBarHosting.maxMisses)
    ) async -> MenuBarHosting.Status {
        let deadline = Date().addingTimeInterval(timeout)
        var misses = 0
        while Date() < deadline {
            if hasHostedStatusItem() {
                return .hosted
            }
            misses += 1
            try? await Task.sleep(nanoseconds: UInt64(MenuBarHosting.pollInterval * 1_000_000_000))
        }
        return MenuBarHosting.status(misses: misses, sawHostedWindow: hasHostedStatusItem())
    }
}
