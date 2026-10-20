import AppKit
import Foundation
import MacBarCore
import ServiceManagement

/// Registers MacBar as a login item using `SMAppService` (macOS 13+).
public final class LoginItemService: LoginItemRegistering, @unchecked Sendable {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            MacBarLog.warning(.app, "login item update failed enabled=\(enabled)")
            throw MacBarError.unknown("无法更新登录项：\(error.localizedDescription)")
        }
    }
}
