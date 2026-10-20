import AppKit
import Foundation
import MacBarCore

/// Provides fallback artwork for status items when a live capture is not
/// available (screen recording not granted, or the window is not shareable).
public struct StatusItemIconProvider: Sendable {
    public init() {}

    /// SF Symbol for well known system items, based on the accessibility title.
    public func symbolName(title: String, fallback: String = "menubar.rectangle") -> String {
        switch title {
        case "Wi-Fi", "WiFi": "wifi"
        case "Battery": "battery.100"
        case "Bluetooth": "wave.3.right"
        case "Sound", "Volume", "Speaker": "speaker.wave.2"
        case "Now Playing": "play.circle"
        case "Focus": "moon"
        case "Screen Mirroring": "airplayvideo"
        case "Keyboard Brightness": "keyboard"
        case "Stage Manager": "rectangle.3.group"
        case "Fast User Switching", "UserSwitcher": "person.crop.circle"
        case "Accessibility Shortcuts": "accessibility"
        case "Music Recognition", "Shazam": "waveform"
        case "Clock": "clock"
        case "Time Machine": "arrow.triangle.2.circlepath"
        case "Passwords": "key"
        case "FaceTime": "video"
        case "Screen Recording", "AudioVideoModule": "record.circle"
        default: fallback
        }
    }

    /// The owning application's icon, used for third-party items without a
    /// capture. Returns a symbol name when no icon is available.
    public func applicationIcon(for pid: Int32) -> NSImage? {
        guard let app = NSRunningApplication(processIdentifier: pid_t(pid)) else { return nil }
        let icon = app.icon ?? NSWorkspace.shared.icon(forFile: app.bundleURL?.path ?? "")
        guard icon.size.width > 1 else { return nil }
        icon.size = NSSize(width: 18, height: 18)
        icon.isTemplate = false
        return icon
    }

    public func image(fromPNG data: Data) -> NSImage? {
        NSImage(data: data)
    }
}
