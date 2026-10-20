import AppKit
import CoreGraphics
import Foundation
import MacBarCore

/// Enumerates status item windows.
///
/// Status items are windows at `CGWindowLevelForKey(.statusWindow)` (25). The
/// window server itself draws the menu bar background at level 24 under the
/// "Window Server" owner, which is filtered out. Items pushed outside the
/// display keep their window; their frame simply moves off screen, which is how
/// macOS stores collapsed items.
public final class CGWindowScanner: MenuBarScanning, @unchecked Sendable {
    private struct RawWindow: Sendable {
        var windowID: UInt32
        var ownerPID: Int32
        var ownerName: String
        var title: String
        var frame: ItemFrame
    }

    private let evaluator: ItemCapabilityEvaluator
    private let axReader: AXMenuBarReader
    private let lock = NSLock()
    private var cachedWindows: [String: RawWindow] = [:]
    private let statusLevel: Int

    public init(evaluator: ItemCapabilityEvaluator = ItemCapabilityEvaluator(), axReader: AXMenuBarReader = AXMenuBarReader()) {
        self.evaluator = evaluator
        self.axReader = axReader
        self.statusLevel = Int(CGWindowLevelForKey(.statusWindow))
    }

    // MARK: - MenuBarScanning

    public func scan(displayID: UInt32?) async throws -> ScanResult {
        let displays = currentDisplays()
        guard !displays.isEmpty else {
            throw MacBarError.notAvailableOnThisSystem
        }
        let primary = displayID.flatMap { id in displays.first { $0.displayID == id } } ?? displays[0]
        // Number unnamed items in left-to-right order so the fallback identity is
        // deterministic for an unchanged menu bar.
        let windows = enumerateWindows().sorted { $0.frame.minX < $1.frame.minX }
        let axItems = axReader.snapshot(for: windows.map(\.ownerPID))

        var records: [MenuBarItemRecord] = []
        var fallbackCounters: [String: Int] = [:]
        for window in windows {
            let owningApp = NSRunningApplication(processIdentifier: pid_t(window.ownerPID))
            let bundleIdentifier = owningApp?.bundleIdentifier
            let namespace = bundleIdentifier ?? window.ownerName
            let ax = AXMenuBarReader.match(frame: window.frame, ownerPID: window.ownerPID, in: axItems)
            let title = ax?.title ?? window.title
            let fallbackIndex = fallbackCounters[namespace, default: 0]
            fallbackCounters[namespace] = fallbackIndex + 1

            let itemID = ItemRegistry.identity(
                bundleIdentifier: bundleIdentifier,
                ownerName: window.ownerName,
                title: title,
                fallbackIndex: fallbackIndex
            )
            guard !records.contains(where: { $0.id == itemID }) else { continue }

            let displayForItem = DisplayAttribution.owner(of: window.frame, among: displays) ?? primary
            if let displayID, displayForItem.displayID != displayID {
                continue
            }
            let isOnScreen = DisplayAttribution.isOnScreen(window.frame, display: displayForItem)

            let isSystemOwned = evaluator.isSystemOwned(bundleIdentifier: bundleIdentifier, ownerName: window.ownerName)
            records.append(
                MenuBarItemRecord(
                    id: itemID,
                    windowID: window.windowID,
                    ownerPID: window.ownerPID,
                    ownerName: window.ownerName,
                    bundleIdentifier: bundleIdentifier,
                    title: title,
                    itemDescription: ax?.itemDescription ?? "",
                    frame: window.frame,
                    displayID: displayForItem.displayID,
                    isOnScreen: isOnScreen,
                    isMovable: evaluator.canMove(bundleIdentifier: bundleIdentifier, title: title),
                    isHideable: evaluator.canHide(bundleIdentifier: bundleIdentifier, title: title),
                    isSystemOwned: isSystemOwned,
                    section: isOnScreen ? .visible : .hidden
                )
            )
        }

        if records.isEmpty, displayID != nil {
            // Fallback for unusual setups where attribution fails: never return
            // an empty list when the window server does have status items.
            MacBarLog.warning(.scan, "attribution yielded no items for display, falling back to all windows")
            return try await scan(displayID: nil)
        }
        records.sort { $0.frame.minX < $1.frame.minX }
        cache(records: records, windows: windows)
        return ScanResult(items: records, accessibilityAvailable: axReader.isTrusted())
    }

    public func frames(for itemIDs: [String]) async -> [String: ItemFrame] {
        guard !itemIDs.isEmpty else { return [:] }
        let wanted = Set(itemIDs)
        let cached = cachedWindowsSnapshot()

        var result: [String: ItemFrame] = [:]
        let windows = enumerateWindows().sorted { $0.frame.minX < $1.frame.minX }
        var fallbackCounters: [String: Int] = [:]
        for window in windows {
            let owningApp = NSRunningApplication(processIdentifier: pid_t(window.ownerPID))
            let bundleIdentifier = owningApp?.bundleIdentifier
            let namespace = bundleIdentifier ?? window.ownerName
            let cachedTitle = cached.first(where: { $0.value.windowID == window.windowID })?.value.title ?? window.title
            let fallbackIndex = fallbackCounters[namespace, default: 0]
            fallbackCounters[namespace] = fallbackIndex + 1
            let itemID = ItemRegistry.identity(
                bundleIdentifier: bundleIdentifier,
                ownerName: window.ownerName,
                title: cachedTitle,
                fallbackIndex: fallbackIndex
            )
            if wanted.contains(itemID) {
                result[itemID] = window.frame
            }
        }
        return result
    }

    public func displayGeometries() async -> [DisplayGeometry] {
        currentDisplays()
    }

    public func mainDisplay() async -> DisplayGeometry {
        let displays = currentDisplays()
        return displays.first { $0.isMain } ?? displays.first ?? .unknown
    }

    // MARK: - Enumeration

    private func enumerateWindows() -> [RawWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        return list.compactMap { info -> RawWindow? in
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == statusLevel else { return nil }
            guard let ownerName = info[kCGWindowOwnerName as String] as? String else { return nil }
            guard ownerName != "Window Server" else { return nil }
            guard let boundsDict = info[kCGWindowBounds as String] as? [String: Any],
                  let bounds = CGRect(dictionaryRepresentation: boundsDict as CFDictionary) else {
                return nil
            }
            let windowID = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value ?? 0
            guard windowID != 0 else { return nil }
            let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value ?? 0
            let title = (info[kCGWindowName as String] as? String) ?? ""
            return RawWindow(
                windowID: windowID,
                ownerPID: ownerPID,
                ownerName: ownerName,
                title: title,
                frame: ItemFrame(x: bounds.origin.x, y: bounds.origin.y, width: bounds.width, height: bounds.height)
            )
        }
    }

    private func currentDisplays() -> [DisplayGeometry] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else { return [] }
        let menuBarHeight = max(Double(NSStatusBar.system.thickness), 24)
        return ids.prefix(Int(count)).map { id in
            let bounds = CGDisplayBounds(id)
            return DisplayGeometry(
                displayID: UInt32(id),
                bounds: ItemFrame(
                    x: bounds.origin.x,
                    y: bounds.origin.y,
                    width: bounds.width,
                    height: bounds.height
                ),
                menuBarHeight: menuBarHeight,
                isMain: CGDisplayIsMain(id) != 0
            )
        }
    }

    private func cachedWindowsSnapshot() -> [String: RawWindow] {
        lock.lock()
        defer { lock.unlock() }
        return cachedWindows
    }

    private func cache(records: [MenuBarItemRecord], windows: [RawWindow]) {
        lock.lock()
        defer { lock.unlock() }
        var map: [String: RawWindow] = [:]
        let windowsByID = Dictionary(uniqueKeysWithValues: windows.map { ($0.windowID, $0) })
        for record in records {
            if let window = windowsByID[record.windowID] {
                map[record.id] = window
            }
        }
        cachedWindows = map
    }
}
