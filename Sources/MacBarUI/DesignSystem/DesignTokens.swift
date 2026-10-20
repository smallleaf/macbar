import AppKit
import MacBarCore
import SwiftUI

/// Visual tokens for the panel and settings windows.
///
/// Following macOS HIG: AppKit supplies most system colours, SwiftUI provides
/// semantic colours that adapt to light/dark appearance automatically.
public enum DesignTokens {
    public enum Spacing {
        public static let xs: CGFloat = 4
        public static let s: CGFloat = 8
        public static let m: CGFloat = 12
        public static let l: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 28
    }

    public enum Radius {
        public static let small: CGFloat = 6
        public static let medium: CGFloat = 10
        public static let large: CGFloat = 14
    }

    public enum Panel {
        public static let width: CGFloat = 440
        public static let maxHeight: CGFloat = 620
        public static let tileHeight: CGFloat = 74
        public static let tileMinWidth: CGFloat = 118
    }

    public enum Typography {
        public static let title = Font.system(size: 15, weight: .semibold)
        public static let sectionTitle = Font.system(size: 11, weight: .semibold)
        public static let body = Font.system(size: 12)
        public static let caption = Font.system(size: 10.5)
        public static let mono = Font.system(size: 10.5, design: .monospaced)
    }

    public enum Colors {
        public static let visible = Color(nsColor: .systemGreen)
        public static let hidden = Color(nsColor: .systemOrange)
        public static let alwaysHidden = Color(nsColor: .systemRed)
        public static let accent = Color.accentColor
        public static let warningBackground = Color(nsColor: .systemYellow).opacity(0.14)
        public static let errorBackground = Color(nsColor: .systemRed).opacity(0.12)
        public static let infoBackground = Color(nsColor: .systemBlue).opacity(0.10)
        public static let card = Color(nsColor: .controlBackgroundColor)
        public static let separator = Color(nsColor: .separatorColor)

        public static func tint(for section: MenuBarSection) -> Color {
            switch section {
            case .visible: visible
            case .hidden: hidden
            case .alwaysHidden: alwaysHidden
            }
        }
    }

    public static let cornerStyle: RoundedCornerStyle = .continuous
}
