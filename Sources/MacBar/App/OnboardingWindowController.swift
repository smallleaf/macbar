import AppKit
import MacBarUI
import SwiftUI

/// First launch flow, shown in a normal window so it can be read comfortably.
@MainActor
final class OnboardingWindowController: NSWindowController, NSWindowDelegate {
    private let model: AppModel
    private var completion: (() -> Void)?

    init(model: AppModel) {
        self.model = model
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "欢迎使用 MacBar"
        window.isReleasedWhenClosed = false
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.center()
        super.init(window: window)
        window.delegate = self

        let root = OnboardingView { [weak self] in
            self?.finish()
        }
        .environmentObject(model)
        window.contentView = NSHostingView(rootView: root)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(onFinish: @escaping () -> Void) {
        completion = onFinish
        window?.makeKeyAndOrderFront(nil)
    }

    private func finish() {
        let callback = completion
        completion = nil
        window?.close()
        callback?()
    }

    func windowWillClose(_ notification: Notification) {
        if let completion {
            self.completion = nil
            model.completeOnboarding()
            completion()
        }
    }
}
