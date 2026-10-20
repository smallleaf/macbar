import AppKit
import CoreGraphics
import Foundation
import MacBarCore

/// Synthesizes mouse drags that move status items.
///
/// Menu bar items are ordinary windows; macOS has no public API to reposition
/// another application's item, but the window server accepts a synthetic
/// mouse-down/drag/up sequence that starts inside the item. The events carry the
/// target window ID so the window server routes them to the item even while the
/// pointer travels outside the menu bar.
public final class CGEventMover: MenuBarMoving, @unchecked Sendable {
    private let axReader: AXMenuBarReader
    private let lock = NSLock()
    private var cursorHidden = false
    private var savedLocation: CGPoint?

    /// Field used by the window server to identify the window under the pointer.
    private static let windowIDField = CGEventField(rawValue: 0x33)!

    public init(axReader: AXMenuBarReader = AXMenuBarReader()) {
        self.axReader = axReader
    }

    public func isEventPostingAvailable() -> Bool {
        axReader.isTrusted()
    }

    // MARK: - MenuBarMoving

    public func drag(itemID: String, windowID: UInt32, ownerPID: Int32, from: ItemPoint, to: ItemPoint) async throws {
        guard axReader.isTrusted() else {
            throw MacBarError.accessibilityDenied
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw MacBarError.eventCreationFailed
        }
        let start = CGPoint(x: from.x, y: from.y)
        let end = CGPoint(x: to.x, y: to.y)

        guard
            let down = makeEvent(type: .leftMouseDown, location: start, windowID: windowID, ownerPID: ownerPID, source: source),
            let firstDrag = makeEvent(type: .leftMouseDragged, location: CGPoint(x: start.x + 1, y: start.y), windowID: windowID, ownerPID: ownerPID, source: source),
            let midDrag = makeEvent(type: .leftMouseDragged, location: CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2), windowID: windowID, ownerPID: ownerPID, source: source),
            let lastDrag = makeEvent(type: .leftMouseDragged, location: end, windowID: windowID, ownerPID: ownerPID, source: source),
            let up = makeEvent(type: .leftMouseUp, location: end, windowID: windowID, ownerPID: ownerPID, source: source)
        else {
            throw MacBarError.eventCreationFailed
        }

        beginPointerIsolation()
        defer { endPointerIsolation() }

        down.post(tap: .cghidEventTap)
        try await sleep(30)
        firstDrag.post(tap: .cghidEventTap)
        try await sleep(25)
        midDrag.post(tap: .cghidEventTap)
        try await sleep(35)
        lastDrag.post(tap: .cghidEventTap)
        try await sleep(40)
        up.post(tap: .cghidEventTap)
        try await sleep(30)
        MacBarLog.info(.move, "drag posted item=\(MacBarLog.sanitize(itemID)) target=\(Int(end.x)),\(Int(end.y))")
    }

    public func click(itemID: String, windowID: UInt32, ownerPID: Int32, at: ItemPoint, button: MouseButton) async throws {
        guard axReader.isTrusted() else {
            throw MacBarError.accessibilityDenied
        }
        guard let source = CGEventSource(stateID: .hidSystemState) else {
            throw MacBarError.eventCreationFailed
        }
        let location = CGPoint(x: at.x, y: at.y)
        let downType: CGEventType = button == .left ? .leftMouseDown : .rightMouseDown
        let upType: CGEventType = button == .left ? .leftMouseUp : .rightMouseUp
        guard
            let down = makeEvent(type: downType, location: location, windowID: windowID, ownerPID: ownerPID, source: source),
            let up = makeEvent(type: upType, location: location, windowID: windowID, ownerPID: ownerPID, source: source)
        else {
            throw MacBarError.eventCreationFailed
        }
        if button == .left {
            down.setIntegerValueField(.mouseEventClickState, value: 1)
            up.setIntegerValueField(.mouseEventClickState, value: 1)
        }
        beginPointerIsolation()
        defer { endPointerIsolation() }
        down.post(tap: .cghidEventTap)
        try await sleep(40)
        up.post(tap: .cghidEventTap)
    }

    /// A plain pointer click used to coax the window server into re-laying out
    /// an item that did not move on the first attempt.
    public func wakeUp(itemID: String, windowID: UInt32, ownerPID: Int32, at: ItemPoint) async throws {
        guard axReader.isTrusted() else { return }
        guard let source = CGEventSource(stateID: .hidSystemState) else { return }
        let location = CGPoint(x: at.x, y: at.y + 40)
        guard
            let down = makeEvent(type: .leftMouseDown, location: location, windowID: windowID, ownerPID: ownerPID, source: source),
            let up = makeEvent(type: .leftMouseUp, location: location, windowID: windowID, ownerPID: ownerPID, source: source)
        else { return }
        down.post(tap: .cghidEventTap)
        try await sleep(30)
        up.post(tap: .cghidEventTap)
    }

    // MARK: - Internals

    private func makeEvent(
        type: CGEventType,
        location: CGPoint,
        windowID: UInt32,
        ownerPID: Int32,
        source: CGEventSource
    ) -> CGEvent? {
        let button: CGMouseButton
        switch type {
        case .rightMouseDown, .rightMouseUp, .rightMouseDragged:
            button = .right
        default:
            button = .left
        }
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: button) else {
            return nil
        }
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(ownerPID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: Int64(windowID))
        event.setIntegerValueField(Self.windowIDField, value: Int64(windowID))
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        return event
    }

    /// Hides the cursor and detaches it from the physical mouse for the duration
    /// of the drag. A user moving the mouse would otherwise cancel the drag.
    private func beginPointerIsolation() {
        lock.lock()
        defer { lock.unlock() }
        guard !cursorHidden else { return }
        savedLocation = CGEvent(source: nil)?.location
        CGAssociateMouseAndMouseCursorPosition(0)
        CGDisplayHideCursor(CGMainDisplayID())
        cursorHidden = true
    }

    private func endPointerIsolation() {
        lock.lock()
        defer { lock.unlock() }
        guard cursorHidden else { return }
        CGAssociateMouseAndMouseCursorPosition(1)
        if let location = savedLocation {
            CGWarpMouseCursorPosition(location)
        }
        CGDisplayShowCursor(CGMainDisplayID())
        cursorHidden = false
        savedLocation = nil
    }

    private func sleep(_ milliseconds: Int) async throws {
        try await Task.sleep(nanoseconds: UInt64(max(0, milliseconds)) * 1_000_000)
    }
}
