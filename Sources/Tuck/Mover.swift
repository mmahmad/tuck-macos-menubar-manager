import Cocoa

/// Moves another app's menu bar item by replaying the ⌘-drag the user would do by hand,
/// addressed straight at the item's window so it also works for items that are off screen.
enum Mover {
    enum Destination {
        case leftOf(CGRect)
        case rightOf(CGRect)
    }

    struct Window {
        let id: CGWindowID
        let pid: pid_t
        let bounds: CGRect
    }

    /// The menu bar window occupying `frame`. Accessibility frames can be a point wider than the window on each side,
    /// so windows are matched on their horizontal centre.
    static func window(at frame: CGRect) -> Window? {
        guard let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard window[kCGWindowLayer as String] as? Int == 25,
                  window[kCGWindowOwnerName as String] as? String != "Window Server",
                  let dict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: dict),
                  abs(bounds.midX - frame.midX) < 1.5, abs(bounds.width - frame.width) < 2.5,
                  let id = window[kCGWindowNumber as String] as? CGWindowID,
                  let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            return Window(id: id, pid: pid, bounds: bounds)
        }
        return nil
    }

    @discardableResult
    static func move(itemAt itemFrame: CGRect, to destination: Destination) -> Bool {
        let targetFrame: CGRect
        let endX: CGFloat
        switch destination {
        case .leftOf(let frame): targetFrame = frame; endX = frame.minX
        case .rightOf(let frame): targetFrame = frame; endX = frame.maxX
        }
        guard let item = window(at: itemFrame), let target = window(at: targetFrame),
              let source = CGEventSource(stateID: .hidSystemState) else { return false }
        // The drag starts far off screen so the real pointer is never seen grabbing anything.
        let start = CGPoint(x: 20_000, y: 20_000)
        let end = CGPoint(x: endX, y: target.bounds.midY)
        guard let down = event(.leftMouseDown, at: start, window: item, flags: .maskCommand, source: source),
              let up = event(.leftMouseUp, at: end, window: target, flags: [], source: source) else { return false }

        let cursor = CGEvent(source: nil)?.location
        for event in [down, up] {
            event.postToPid(item.pid)
            usleep(30_000)
            event.post(tap: .cgSessionEventTap)
            usleep(30_000)
        }
        if let cursor { CGWarpMouseCursorPosition(cursor) }
        return true
    }

    private static func event(_ type: CGEventType, at location: CGPoint, window: Window, flags: CGEventFlags, source: CGEventSource) -> CGEvent? {
        guard let event = CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: location, mouseButton: .left) else { return nil }
        event.flags = flags
        let id = Int64(window.id)
        event.setIntegerValueField(.eventTargetUnixProcessID, value: Int64(window.pid))
        event.setIntegerValueField(.mouseEventWindowUnderMousePointer, value: id)
        event.setIntegerValueField(.mouseEventWindowUnderMousePointerThatCanHandleThisEvent, value: id)
        if let windowIDField = CGEventField(rawValue: 0x33) { event.setIntegerValueField(windowIDField, value: id) }
        return event
    }
}
