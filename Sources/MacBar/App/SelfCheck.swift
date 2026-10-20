import Foundation
import MacBarCore
import MacBarSystem

/// Headless environment checks.
///
/// `--self-check` never synthesizes events and never requests permissions. It
/// answers the question "can this build see the menu bar on this machine?" and
/// prints a report that can be attached to a bug ticket.
enum SelfCheck {
    static func run() {
        print("MacBar self-check")
        print("app version: \(MacBarVersion.current) (\(MacBarVersion.build))")
        print("macOS: \(ProcessInfo.processInfo.operatingSystemVersionString)")
        print("architecture: \(architecture())")
        print("hardware: \(DiagnosticsReport.hardwareModel())")
        print("")

        let group = DispatchGroup()
        group.enter()

        Task {
            let scanner = CGWindowScanner()
            let permissions = TCCPermissionChecker()
            print("[permissions]")
            for kind in PermissionKind.allCases {
                print("  \(kind.rawValue): \(permissions.status(of: kind).rawValue)")
            }
            print("")

            let displays = await scanner.displayGeometries()
            print("[displays] count=\(displays.count)")
            for display in displays {
                print(
                    "  id=\(display.displayID) main=\(display.isMain) bounds=(\(Int(display.bounds.x)),\(Int(display.bounds.y)),\(Int(display.bounds.width)),\(Int(display.bounds.height))) menuBarHeight=\(Int(display.menuBarHeight))"
                )
            }
            print("")

            do {
                let result = try await scanner.scan(displayID: displays.first(where: \.isMain)?.displayID)
                print("[status items] count=\(result.items.count) accessibility=\(result.accessibilityAvailable)")
                let engine = LayoutEngine()
                let anchors = engine.synthesizedAnchors(display: displays.first(where: \.isMain) ?? .unknown)
                for item in result.items {
                    let section = engine.deriveSection(for: item.frame, anchors: anchors)
                    print(
                        "  id=\(MacBarLog.sanitize(item.id)) owner=\(MacBarLog.sanitize(item.ownerName)) section=\(section.rawValue) frame=(\(Int(item.frame.x)),\(Int(item.frame.y)),\(Int(item.frame.width)),\(Int(item.frame.height))) movable=\(item.isMovable) hideable=\(item.isHideable)"
                    )
                }
                print("")
                let visible = result.items.filter { engine.deriveSection(for: $0.frame, anchors: anchors) == .visible }
                let hideable = visible.filter { $0.isHideable && $0.isMovable }
                print("[summary] visible=\(visible.count) hideable=\(hideable.count)")
                print(result.items.isEmpty ? "RESULT: FAIL no status items" : "RESULT: OK")
            } catch {
                print("scan failed: \(error)")
                print("RESULT: FAIL")
            }

            group.leave()
        }

        while group.wait(timeout: .now()) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
    }

    private static func architecture() -> String {
        #if arch(arm64)
        "arm64"
        #elseif arch(x86_64)
        "x86_64"
        #else
        "unknown"
        #endif
    }
}
