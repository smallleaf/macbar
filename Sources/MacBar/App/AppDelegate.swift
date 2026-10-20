import AppKit
import Foundation
import MacBarCore
import MacBarSystem
import MacBarUI

/// Application lifecycle and wiring.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    struct LaunchOptions {
        var showOnboarding: Bool = true
        /// Opens the management panel immediately, used for UI verification.
        var showPanelAtLaunch: Bool = false
        /// When set, the app starts headless-ish (no windows) to validate runtime
        /// wiring in CI and quits after the given number of seconds.
        var autoQuitAfter: Double?

        /// True when no user-facing window must be opened.
        var isSmokeTest: Bool { autoQuitAfter != nil }
    }

    private let options: LaunchOptions
    private var environment: AppEnvironment?
    private var observers: [NSObjectProtocol] = []
    private var terminationInProgress = false

    init(options: LaunchOptions = LaunchOptions()) {
        self.options = options
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let environment = AppEnvironment()
        self.environment = environment
        Self.installMainMenu()
        environment.start(
            showOnboarding: options.showOnboarding,
            smokeTest: options.isSmokeTest,
            showPanelAtLaunch: options.showPanelAtLaunch
        )
        registerWorkspaceObservers()
        MacBarLog.info(.app, "launched version=\(MacBarVersion.current)")

        if let delay = options.autoQuitAfter {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                print("SMOKE: terminating")
                NSApp.terminate(nil)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        environment?.stop()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let settings = environment?.model.settings else { return .terminateNow }
        if settings.restoreOnQuit && !terminationInProgress {
            terminationInProgress = true
            environment?.model.emergencyRestore()
            // Give the restore a moment to finish before the process exits.
            DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
                sender.reply(toApplicationShouldTerminate: true)
            }
            return .terminateLater
        }
        return .terminateNow
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        environment?.showPanel()
        return true
    }

    /// Status items vanish when the display configuration changes; resync the
    /// anchors and refresh the panel data.
    private func registerWorkspaceObservers() {
        let center = NSWorkspace.shared.notificationCenter
        let names: [NSNotification.Name] = [
            NSWorkspace.didLaunchApplicationNotification,
            NSWorkspace.didTerminateApplicationNotification,
            NSWorkspace.activeSpaceDidChangeNotification,
            NSApplication.didChangeScreenParametersNotification,
            NSWorkspace.didWakeNotification,
        ]
        for name in names {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let environment = self.environment else { return }
                    environment.statusItems.syncAnchors()
                    environment.model.updateAnchors(environment.statusItems.anchors)
                    await environment.model.refresh()
                    environment.statusItems.updateHiddenCount(environment.model.hiddenCount)
                }
            }
            observers.append(observer)
        }
        let screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let environment = self.environment else { return }
                environment.statusItems.rebuild()
                environment.model.updateAnchors(environment.statusItems.anchors)
                await environment.model.refresh()
            }
        }
        observers.append(screenObserver)
    }

    /// Minimal main menu so standard shortcuts (copy/paste/quit) work in the
    /// settings window even though the app runs as an accessory.
    private static func installMainMenu() {
        let mainMenu = NSMenu()
        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 MacBar", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 MacBar", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu

        let editMenuItem = NSMenuItem()
        mainMenu.addItem(editMenuItem)
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "重做", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editMenuItem.submenu = editMenu

        NSApp.mainMenu = mainMenu
    }
}
