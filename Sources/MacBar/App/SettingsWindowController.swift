import AppKit
import MacBarUI
import SwiftUI

/// Regular window that hosts the settings tabs.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    typealias Tab = SettingsTab

    private let model: AppModel
    private var currentTab: Tab = .general
    private var hosting: NSHostingView<AnyView>?

    var onOpenPanel: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 460),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "MacBar 设置"
        window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        window.delegate = self
        installContent()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func installContent() {
        let root = SettingsRootView(
            selection: Binding(
                get: { self.currentTab },
                set: { self.currentTab = $0 }
            ),
            onOpenPanel: { [weak self] in self?.onOpenPanel?() }
        )
        .environmentObject(model)
        let hosting = NSHostingView(rootView: AnyView(root))
        window?.contentView = hosting
        self.hosting = hosting
    }

    func show(tab: Tab? = nil) {
        if let tab {
            currentTab = tab
            installContent()
        }
        if !model.hasCompletedOnboarding {
            model.completeOnboarding()
        }
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
