import AppKit
import MacBarCore

/// Entry point. `--self-check` runs a headless, read-only scan so CI and
/// developers can verify the window enumeration path without granting
/// Accessibility permission or touching the menu bar.
@main
enum MacBarApp {
    @MainActor
    static func main() {
        // Unbuffered stdout so diagnostic output is visible when the app is
        // launched from a terminal or a log collector.
        setvbuf(stdout, nil, _IONBF, 0)
        let arguments = CommandLine.arguments
        if arguments.contains("--self-check") {
            SelfCheck.run()
            return
        }
        if arguments.contains("--version") {
            print("MacBar \(MacBarVersion.current) (\(MacBarVersion.build))")
            return
        }
        if arguments.contains("--diagnostics") {
            let store = JSONLayoutStore()
            if let url = try? store.exportDiagnostics() {
                print(url.path)
            } else {
                print("diagnostics export failed")
            }
            return
        }

        let smokeIndex = arguments.firstIndex(of: "--smoke")
        let options = AppDelegate.LaunchOptions(
            showOnboarding: smokeIndex == nil && !arguments.contains("--show-panel"),
            showPanelAtLaunch: arguments.contains("--show-panel"),
            autoQuitAfter: smokeIndex.map { index in
                let value = arguments.indices.contains(index + 1) ? Double(arguments[index + 1]) : nil
                return value ?? 8
            }
        )

        let application = NSApplication.shared
        let delegate = AppDelegate(options: options)
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
