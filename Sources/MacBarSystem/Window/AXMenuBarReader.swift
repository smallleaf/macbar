import AppKit
import CoreGraphics
import Foundation
import MacBarCore

/// Reads status item titles through the Accessibility API.
///
/// `AXExtrasMenuBar` exposes the children of a menu bar. Each child carries a
/// frame and, for system items, a human readable title such as "Wi-Fi". Window
/// frames from `CGWindowList` and AX frames use the same coordinate space, so
/// items can be matched by frame with a small tolerance.
public struct AXMenuBarReader: Sendable {
    public struct AXItem: Sendable, Hashable {
        public var ownerPID: Int32
        public var title: String
        public var itemDescription: String
        public var frame: ItemFrame
    }

    public init() {}

    public func isTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// Collects titles for every process that owns a menu bar item.
    public func snapshot(for ownerPIDs: [Int32]) -> [AXItem] {
        guard isTrusted() else { return [] }
        var results: [AXItem] = []
        for pid in Set(ownerPIDs) where pid > 0 {
            results.append(contentsOf: items(ownerPID: pid))
        }
        return results
    }

    private func items(ownerPID: Int32) -> [AXItem] {
        let app = AXUIElementCreateApplication(pid_t(ownerPID))
        var extrasRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXExtrasMenuBarAttribute as CFString, &extrasRef) == .success,
              let extrasRef else {
            return []
        }
        let extras = unsafeDowncast(extrasRef, to: AXUIElement.self)
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(extras, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else {
            return []
        }
        return children.compactMap { child in
            guard let frame = frame(of: child) else { return nil }
            let title = stringAttribute(kAXTitleAttribute, of: child)
            let description = stringAttribute(kAXDescriptionAttribute, of: child)
            return AXItem(
                ownerPID: ownerPID,
                title: title ?? "",
                itemDescription: description ?? "",
                frame: frame
            )
        }
    }

    private func frame(of element: AXUIElement) -> ItemFrame? {
        var positionRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionRef) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let positionRef, let sizeRef else {
            return nil
        }
        var point = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(unsafeDowncast(positionRef, to: AXValue.self), .cgPoint, &point),
              AXValueGetValue(unsafeDowncast(sizeRef, to: AXValue.self), .cgSize, &size) else {
            return nil
        }
        return ItemFrame(x: point.x, y: point.y, width: size.width, height: size.height)
    }

    private func stringAttribute(_ attribute: String, of element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else {
            return nil
        }
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    /// Matches an AX item to a window frame, preferring the same owner.
    public static func match(frame: ItemFrame, ownerPID: Int32, in items: [AXItem]) -> AXItem? {
        items
            .filter { $0.ownerPID == ownerPID }
            .min { lhs, rhs in
                distance(lhs.frame, frame) < distance(rhs.frame, frame)
            }
            .flatMap { candidate in
                distance(candidate.frame, frame) <= 4 ? candidate : nil
            }
    }

    private static func distance(_ lhs: ItemFrame, _ rhs: ItemFrame) -> Double {
        abs(lhs.minX - rhs.minX) + abs(lhs.minY - rhs.minY) + abs(lhs.width - rhs.width)
    }
}
