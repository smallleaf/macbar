import AppKit
import MacBarCore
import MacBarSystem
import MacBarUI

/// Owns the primary control item and derives the layout boundaries.
///
/// ## Why there are no separator items
///
/// The plan proposed two invisible separator items whose positions would act as
/// section boundaries. Testing on macOS 26.2 showed that the system itself stores
/// collapsed items to the left of the display at negative `x` (Control Center
/// items sat at `x = -398 ... -794`), and that an item placed left of a separator
/// inside the bar simply stays visible. Hiding therefore requires moving items
/// outside the display bounds, not past a separator.
///
/// The boundaries are derived from geometry instead:
/// - `visibleX`: the control item's left edge, visible items are packed to its left.
/// - `hiddenX`: the display's left edge; anything left of it is off screen.
/// - `alwaysHiddenX`: a point 300pt further left; always-hidden items live there.
@MainActor
final class StatusItemController {
    private(set) var controlItem: NSStatusItem?
    private(set) var anchors: LayoutAnchors = .zero

    private var onOpenPanel: (() -> Void)?
    private var onToggleHidden: (() -> Void)?
    private var onOpenSettings: (() -> Void)?
    private var onOpenDiagnostics: (() -> Void)?
    private var onReset: (() -> Void)?
    private var onQuit: (() -> Void)?

    var controlItemButton: NSStatusBarButton? {
        controlItem?.button
    }

    func install(
        onOpenPanel: @escaping () -> Void,
        onToggleHidden: @escaping () -> Void,
        onOpenSettings: @escaping () -> Void,
        onOpenDiagnostics: @escaping () -> Void,
        onReset: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.onOpenPanel = onOpenPanel
        self.onToggleHidden = onToggleHidden
        self.onOpenSettings = onOpenSettings
        self.onOpenDiagnostics = onOpenDiagnostics
        self.onReset = onReset
        self.onQuit = onQuit

        let control = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = control.button {
            button.image = Self.controlImage()
            button.image?.isTemplate = true
            button.imagePosition = .imageOnly
            button.setAccessibilityLabel("MacBar")
            button.target = self
            button.action = #selector(handleControlClick(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "MacBar 菜单栏管理"
        }
        controlItem = control

        syncAnchors()
    }

    func uninstall() {
        if let controlItem {
            NSStatusBar.system.removeStatusItem(controlItem)
        }
        controlItem = nil
    }

    /// Reads the anchors from their windows. Called before opening the panel and
    /// after layout-changing events.
    @discardableResult
    func syncAnchors() -> LayoutAnchors {
        let screen = controlItem?.button?.window?.screen ?? NSScreen.main
        // Global menu bar coordinates start at zero on the main display and grow
        // rightwards; NSScreen.frame uses the same horizontal origin.
        let screenMinX = Double(screen?.frame.minX ?? 0)
        let hiddenX = screenMinX
        let alwaysHiddenX = screenMinX - 300
        // The status item's window is laid out asynchronously: right after
        // creation it reports a zero-sized frame at the origin. Only trust the
        // frame once it has a real width and position.
        let rawVisibleX: Double
        if let frame = controlItem?.button?.window?.frame,
           frame.width > 1, frame.minX > 0 {
            rawVisibleX = Double(frame.minX) - 2
        } else {
            rawVisibleX = Double(screen?.frame.maxX ?? 1440)
        }
        let visibleX = rawVisibleX
        // A full menu bar pushes the control item off screen (visibleX became
        // -2 on macOS 26.2 with the bar packed). Clamp so the plan never places
        // items outside the display on the visible side.
        let clampedVisibleX = max(visibleX, hiddenX + 80)
        let next = LayoutAnchors(
            visibleX: clampedVisibleX,
            hiddenX: hiddenX,
            alwaysHiddenX: alwaysHiddenX
        )
        if next != anchors {
            anchors = next
            MacBarLog.info(
                .layout,
                "anchors updated visibleX=\(Int(next.visibleX)) hiddenX=\(Int(next.hiddenX)) alwaysHiddenX=\(Int(next.alwaysHiddenX ?? 0))"
            )
        }
        return anchors
    }

    /// True when the control item was laid out outside the display, which macOS
    /// 26 does when the menu bar is full or when its menu bar setting is off.
    var isControlItemOffscreen: Bool {
        guard let window = controlItem?.button?.window else { return true }
        let screen = window.screen ?? NSScreen.main
        let minX = screen?.frame.minX ?? 0
        return window.frame.minX < minX
    }

    /// Recreates the items. Used when the system loses track of them, which has
    /// been observed on macOS 26 after login.
    func rebuild() {
        uninstall()
        guard let onOpenPanel, let onToggleHidden, let onOpenSettings,
              let onOpenDiagnostics, let onReset, let onQuit else { return }
        install(
            onOpenPanel: onOpenPanel,
            onToggleHidden: onToggleHidden,
            onOpenSettings: onOpenSettings,
            onOpenDiagnostics: onOpenDiagnostics,
            onReset: onReset,
            onQuit: onQuit
        )
    }

    func updateHiddenCount(_ count: Int) {
        guard let button = controlItem?.button else { return }
        if let image = Self.controlImage(hiddenCount: count) {
            button.image = image
            button.image?.isTemplate = true
        }
        button.toolTip = count > 0 ? "MacBar 菜单栏管理（已隐藏 \(count) 个）" : "MacBar 菜单栏管理"
        button.setAccessibilityValue(count > 0 ? "已隐藏 \(count) 个图标" : "")
    }

    func applyDockPolicy(_ showDockIcon: Bool) {
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
    }

    func fallbackSymbol(for item: MenuBarItemRecord) -> NSImage? {
        let provider = StatusItemIconProvider()
        let name = provider.symbolName(title: item.title)
        return NSImage(systemSymbolName: name, accessibilityDescription: item.displayName)
    }

    // MARK: - Actions

    @objc private func handleControlClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            onOpenPanel?()
            return
        }
        if event.type == .rightMouseUp || event.modifierFlags.contains(.control) {
            presentMenu()
            return
        }
        if event.modifierFlags.contains(.option) {
            onOpenSettings?()
            return
        }
        onOpenPanel?()
    }

    private func presentMenu() {
        let menu = NSMenu()
        let toggle = NSMenuItem(title: "切换隐藏区", action: #selector(menuToggleHidden), keyEquivalent: "")
        toggle.target = self
        menu.addItem(toggle)
        let showAll = NSMenuItem(title: "显示全部图标", action: #selector(menuShowAll), keyEquivalent: "")
        showAll.target = self
        menu.addItem(showAll)
        let reset = NSMenuItem(title: "重置布局", action: #selector(menuReset), keyEquivalent: "")
        reset.target = self
        menu.addItem(reset)
        menu.addItem(.separator())
        let settings = NSMenuItem(title: "设置…", action: #selector(menuSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let diagnostics = NSMenuItem(title: "诊断…", action: #selector(menuDiagnostics), keyEquivalent: "")
        diagnostics.target = self
        menu.addItem(diagnostics)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "退出 MacBar", action: #selector(menuQuit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        controlItem?.menu = menu
        controlItem?.button?.performClick(nil)
        controlItem?.menu = nil
    }

    @objc private func menuToggleHidden() { onToggleHidden?() }
    @objc private func menuShowAll() { onToggleHidden?() }
    @objc private func menuReset() { onReset?() }
    @objc private func menuSettings() { onOpenSettings?() }
    @objc private func menuDiagnostics() { onOpenDiagnostics?() }
    @objc private func menuQuit() { onQuit?() }

    // MARK: - Helpers

    private static func controlImage(hiddenCount: Int = 0) -> NSImage? {
        let symbol = hiddenCount > 0 ? "menubar.rectangle" : "menubar.rectangle"
        guard let image = NSImage(systemSymbolName: symbol, accessibilityDescription: "MacBar") else {
            return nil
        }
        image.isTemplate = true
        // SF Symbols report a zero size until they are drawn. A status item with
        // a zero-sized image gets a zero-height window and never becomes
        // visible, which was observed on macOS 26.2.
        if image.size.width == 0 || image.size.height == 0 {
            image.size = NSSize(width: 18, height: 18)
        }
        return image
    }
}
