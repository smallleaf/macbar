import AppKit
import MacBarUI
import SwiftUI

/// Floating panel anchored under the status item.
///
/// Uses `NSPanel` with `.nonactivatingPanel` so opening the panel does not steal
/// focus from the frontmost app, and closes when the user clicks elsewhere,
/// matching the behaviour of system menus.
@MainActor
final class PanelWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var hosting: NSHostingView<AnyView>?

    var onOpenSettings: (() -> Void)?
    var onOpenDiagnostics: (() -> Void)?
    var onQuit: (() -> Void)?

    var isVisible: Bool { window?.isVisible ?? false }

    init(model: AppModel) {
        self.model = model
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: DesignTokens.Panel.width, height: 520),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.standardWindowButton(.closeButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        super.init(window: panel)
        panel.delegate = self
        installContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func installContent() {
        let root = MenuBarPanelView(
            onOpenSettings: { [weak self] in self?.onOpenSettings?() },
            onOpenDiagnostics: { [weak self] in self?.onOpenDiagnostics?() },
            onQuit: { [weak self] in self?.onQuit?() }
        )
        .environmentObject(model)

        let hosting = NSHostingView(rootView: AnyView(root))
        hosting.wantsLayer = true
        hosting.layer?.cornerRadius = DesignTokens.Radius.large
        hosting.layer?.masksToBounds = true
        window?.contentView = hosting
        self.hosting = hosting
    }

    func show(relativeTo anchor: NSStatusBarButton?) {
        guard let window else { return }
        resizeToFit()

        if let anchor, let anchorWindow = anchor.window, let screen = anchorWindow.screen ?? NSScreen.main {
            let anchorRect = anchorWindow.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let size = window.frame.size
            let visible = screen.visibleFrame
            var originX = anchorRect.midX - size.width / 2
            originX = min(max(originX, visible.minX + 8), visible.maxX - size.width - 8)
            let originY = min(anchorRect.minY - size.height - 6, visible.maxY - size.height - 6)
            window.setFrameOrigin(NSPoint(x: originX, y: originY))
        } else if let screen = NSScreen.main {
            let size = window.frame.size
            let visible = screen.visibleFrame
            window.setFrameOrigin(
                NSPoint(x: visible.maxX - size.width - 12, y: visible.maxY - size.height - 12)
            )
        }

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
        observeResign()
    }

    func dismiss() {
        resignObserver = nil
        window?.orderOut(nil)
    }

    func toggle(relativeTo anchor: NSStatusBarButton?) {
        if isVisible {
            dismiss()
        } else {
            show(relativeTo: anchor)
        }
    }

    private var resignObserver: NSObjectProtocol?

    private func observeResign() {
        resignObserver.map(NotificationCenter.default.removeObserver)
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            // Delay so a click on another control does not close and reopen.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                guard let self, let window = self.window, window.isVisible else { return }
                if !window.isKeyWindow {
                    self.dismiss()
                }
            }
        }
    }

    /// The SwiftUI root has an intrinsic height; the window follows it up to the
    /// documented maximum.
    ///
    /// `fittingSize.height` is not trustworthy for a width-constrained SwiftUI
    /// root: it has been observed to report the maximum height of 620 even when
    /// the content is shorter. The content view's `fittingSize` is used first,
    /// then the result is clamped.
    private func resizeToFit() {
        guard let hosting, let window else { return }
        hosting.layoutSubtreeIfNeeded()
        let contentSize = hosting.fittingSize
        let height = min(max(contentSize.height, 360), DesignTokens.Panel.maxHeight)
        var frame = window.frame
        let top = frame.maxY
        frame.size = NSSize(width: DesignTokens.Panel.width, height: height)
        frame.origin.y = top - height
        window.setFrame(frame, display: false)
    }

    func windowWillClose(_ notification: Notification) {
        resignObserver.map(NotificationCenter.default.removeObserver)
        resignObserver = nil
    }
}
