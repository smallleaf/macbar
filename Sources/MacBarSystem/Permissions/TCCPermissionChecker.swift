import AppKit
import ApplicationServices
import CoreGraphics
import Foundation
import MacBarCore

/// Reads and requests the two TCC permissions MacBar needs.
public final class TCCPermissionChecker: PermissionProviding, @unchecked Sendable {
    private let settingsURLs: [PermissionKind: String] = [
        .accessibility: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility",
        .screenRecording: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
    ]

    public init() {}

    public func status(of kind: PermissionKind) -> PermissionStatus {
        switch kind {
        case .accessibility:
            return AXIsProcessTrusted() ? .granted : .denied
        case .screenRecording:
            return CGPreflightScreenCaptureAccess() ? .granted : .denied
        }
    }

    @discardableResult
    public func request(_ kind: PermissionKind) -> Bool {
        switch kind {
        case .accessibility:
            let promptKey = "AXTrustedCheckOptionPrompt"
            let options = [promptKey: true] as CFDictionary
            let granted = AXIsProcessTrustedWithOptions(options)
            MacBarLog.warning(.permission, "accessibility request result=\(granted)")
            return granted
        case .screenRecording:
            let granted = CGRequestScreenCaptureAccess()
            MacBarLog.warning(.permission, "screen recording request result=\(granted)")
            return granted
        }
    }

    public func openSystemSettings(for kind: PermissionKind) {
        guard let raw = settingsURLs[kind], let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    /// A machine-readable permission summary for the diagnostics export.
    public func snapshot() -> [PermissionKind: PermissionStatus] {
        Dictionary(uniqueKeysWithValues: PermissionKind.allCases.map { ($0, status(of: $0)) })
    }
}
