import AppKit
import MacBarCore
import SwiftUI

/// Icon shown for a status item: live capture, application icon, or a symbol.
public struct ItemIconView: View {
    public let item: MenuBarItemRecord
    public let image: NSImage?
    public var size: CGFloat = 22

    public init(item: MenuBarItemRecord, image: NSImage?, size: CGFloat = 22) {
        self.item = item
        self.image = image
        self.size = size
    }

    public var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: symbol)
                    .font(.system(size: size * 0.62, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var symbol: String {
        if item.isSystemOwned {
            switch item.title {
            case "Wi-Fi", "WiFi": return "wifi"
            case "Battery": return "battery.100"
            case "Bluetooth": return "wave.3.right"
            case "Now Playing": return "play.circle"
            case "Focus": return "moon"
            case "Clock": return "clock"
            case "Screen Mirroring": return "airplayvideo"
            default: return "switch.2"
            }
        }
        return "app.dashed"
    }
}
