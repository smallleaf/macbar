import AppKit
import Foundation
import MacBarCore
import MacBarSystem
import MacBarUI

/// Wires the capability implementations together and owns the long-lived
/// objects (status items, windows, hotkeys) for the app's lifetime.
@MainActor
final class AppEnvironment {
    let store: JSONLayoutStore
    let scanner: CGWindowScanner
    let mover: CGEventMover
    let permissions: TCCPermissionChecker
    let capturer: ScreenCaptureKitCapturer
    let conflictDetector: AppKitConflictDetector
    let loginItem: LoginItemService
    let hotkeys: GlobalHotkeyService
    let iconProvider: StatusItemIconProvider
    let statusItems: StatusItemController
    let model: AppModel
    let panelController: PanelWindowController
    let settingsController: SettingsWindowController
    let onboardingController: OnboardingWindowController

    init() {
        store = JSONLayoutStore()
        scanner = CGWindowScanner()
        mover = CGEventMover()
        permissions = TCCPermissionChecker()
        capturer = ScreenCaptureKitCapturer()
        conflictDetector = AppKitConflictDetector()
        loginItem = LoginItemService()
        hotkeys = GlobalHotkeyService()
        iconProvider = StatusItemIconProvider()
        statusItems = StatusItemController()

        let model = AppModel(
            scanner: scanner,
            mover: mover,
            permissions: permissions,
            store: store,
            capturer: capturer,
            conflictDetector: conflictDetector,
            loginItem: loginItem,
            iconProvider: { [provider = iconProvider, weak statusItems] item in
                if let icon = provider.applicationIcon(for: item.ownerPID) {
                    return icon
                }
                return statusItems?.fallbackSymbol(for: item)
            },
            modeListener: { _ in }
        )
        self.model = model
        model.hostingProbe = { await StatusItemHostChecker().waitForHosting(timeout: 3) }
        panelController = PanelWindowController(model: model)
        settingsController = SettingsWindowController(model: model)
        onboardingController = OnboardingWindowController(model: model)

        statusItems.install(
            onOpenPanel: { [weak self] in self?.showPanel() },
            onToggleHidden: { [weak self] in
                guard let self else { return }
                if self.model.hiddenCount > 0 {
                    self.model.showAll()
                } else {
                    self.model.hideAll()
                }
            },
            onOpenSettings: { [weak self] in self?.showSettings() },
            onOpenDiagnostics: { [weak self] in
                self?.showSettings(tab: .diagnostics)
            },
            onReset: { [weak self] in self?.model.resetLayout() },
            onQuit: { NSApp.terminate(nil) }
        )

        panelController.onOpenSettings = { [weak self] in
            guard let self else { return }
            // A rebuild invalidates the grant; land on the tab that explains
            // how to fix it instead of the general settings.
            self.showSettings(tab: self.model.needsReauthorizationAfterRebuild ? .permissions : nil)
        }
        panelController.onOpenDiagnostics = { [weak self] in self?.showSettings(tab: .diagnostics) }
        panelController.onQuit = { NSApp.terminate(nil) }
        settingsController.onOpenPanel = { [weak self] in self?.showPanel() }

        hotkeys.setHandler { [weak self] action in
            Task { @MainActor in
                guard let self else { return }
                switch action {
                case .toggleHidden:
                    if self.model.hiddenCount > 0 {
                        self.model.showAll()
                    } else {
                        self.model.hideAll()
                    }
                case .emergencyRestore:
                    self.model.emergencyRestore()
                }
            }
        }
    }

    func start(showOnboarding: Bool = true, smokeTest: Bool = false, showPanelAtLaunch: Bool = false) {
        let signature = CodeSignature.current()
        model.setSignature(signature)
        MacBarLog.warning(.app, "signature adhoc=\(signature.isAdHoc) fingerprint=\(signature.shortFingerprint)")
        statusItems.updateHiddenCount(0)
        Task { [weak self] in
            guard let self else { return }
            await self.model.start()
            // Give the window server a beat to lay out the status item, then
            // re-read the boundaries it defines.
            try? await Task.sleep(nanoseconds: 400_000_000)
            self.statusItems.syncAnchors()
            self.model.updateAnchors(self.statusItems.anchors)
            await self.model.refresh()
            self.statusItems.updateHiddenCount(self.model.hiddenCount)
            self.statusItems.applyDockPolicy(self.model.settings.showDockIcon)
            self.registerHotkeys()
            let checker = StatusItemHostChecker()
            let hosting = await checker.waitForHosting()
            self.model.setHostingStatus(hosting)

            if smokeTest {
                print("SMOKE: mode=\(self.model.mode.rawValue) items=\(self.model.items.count) visible=\(self.model.items(in: .visible).count) hideable=\(self.model.hideableCount)")
                print("SMOKE: accessibility=\(self.model.accessibilityStatus.rawValue) conflicts=\(self.model.conflicts)")
                print("SMOKE: signature adhoc=\(self.model.signature.isAdHoc) fingerprint=\(self.model.signature.shortFingerprint) needsReauth=\(self.model.needsReauthorizationAfterRebuild)")
                print("SMOKE: anchors visibleX=\(Int(self.statusItems.anchors.visibleX)) hiddenX=\(Int(self.statusItems.anchors.hiddenX))")
                print("SMOKE: controlItem=\(self.statusItems.controlItem != nil) frame=\(String(describing: self.statusItems.controlItem?.button?.window?.frame)) image=\(String(describing: self.statusItems.controlItem?.button?.image?.size))")
                print("SMOKE: hosting=\(hosting.rawValue)")
                self.model.emergencyRestore()
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                print("SMOKE: restore finished lastError=\(self.model.lastError?.code ?? "none")")
                return
            }
            // A missing hosted window means the system is refusing to show the
            // icon (macOS 26 allow-list). Explain that instead of repeatedly
            // asking for Accessibility.
            if hosting == .notHosted, !self.model.settings.hasShownMenuBarAllowListGuidance {
                self.model.markAllowListGuidanceShown()
                self.showAllowListGuidance()
            }
            if showPanelAtLaunch {
                self.showPanel()
                return
            }
            if showOnboarding && !self.model.hasCompletedOnboarding {
                self.showOnboarding()
            }
        }
    }

    func stop() {
        hotkeys.unregisterAll()
        model.stop()
        statusItems.uninstall()
    }

    func registerHotkeys() {
        let invalid = hotkeys.register(
            defaults: HotkeyDefaults(
                toggleHidden: model.settings.hotkeyToggleHidden,
                emergencyRestore: model.settings.hotkeyEmergencyRestore
            )
        )
        if !invalid.isEmpty {
            MacBarLog.warning(.hotkey, "invalid hotkey count=\(invalid.count)")
        }
    }

    func showPanel() {
        statusItems.syncAnchors()
        model.updateAnchors(statusItems.anchors)
        panelController.show(relativeTo: statusItems.controlItemButton)
    }

    func togglePanel() {
        if panelController.isVisible {
            panelController.dismiss()
        } else {
            showPanel()
        }
    }

    func showSettings(tab: SettingsWindowController.Tab? = nil) {
        settingsController.show(tab: tab)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Explains the macOS 26 menu bar allow-list when the status item is not
    /// being shown, and opens the corresponding System Settings pane.
    func showAllowListGuidance() {
        let alert = NSAlert()
        alert.messageText = "macOS 未在菜单栏中显示 MacBar"
        alert.informativeText = """
        从 macOS 26 开始，菜单栏由系统统一管理。如果 MacBar 没有出现在菜单栏中，请在「系统设置 → 菜单栏」的「允许在菜单栏中显示」列表里启用 MacBar。

        如果已经启用仍不显示，请先关闭再重新打开该开关。
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "打开菜单栏设置")
        alert.addButton(withTitle: "稍后处理")
        if alert.runModal() == .alertFirstButtonReturn {
            model.openMenuBarSettings()
        }
    }

    func showOnboarding() {
        onboardingController.show { [weak self] in
            self?.showPanel()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
