import ApplicationServices
import Cocoa

/// Opens another app's menu bar item on the user's behalf.
enum Activator {
    /// Presses the item through accessibility, falling back to a simulated click when the app rejects that.
    static func press(_ item: MenuBarItem, forceClick: Bool = false) {
        DispatchQueue.global(qos: .userInitiated).async {
            if !forceClick {
                let result = AXUIElementPerformAction(item.element, kAXPressAction as CFString)
                // An item that opens a menu keeps the call blocked until the menu closes, which reports as a timeout.
                if result == .success || result == .cannotComplete { return }
            }
            DispatchQueue.main.async { click(item) }
        }
    }

    private static func click(_ item: MenuBarItem) {
        // The cached frame predates any reveal, so ask again.
        guard let frame = AX.frame(item.element),
              NSScreen.screens.contains(where: { $0.frame.minX <= frame.midX && frame.midX <= $0.frame.maxX }) else {
            NSSound.beep()
            return
        }
        let target = CGPoint(x: frame.midX, y: frame.midY)
        let original = CGEvent(source: nil)?.location
        let source = CGEventSource(stateID: .hidSystemState)
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: source, mouseType: type, mouseCursorPosition: target, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        if let original {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { CGWarpMouseCursorPosition(original) }
        }
    }

    /// Whether the app currently has a menu or popover on screen.
    static func hasOpenMenu(pid: pid_t) -> Bool {
        guard let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID) as? [[String: Any]] else { return false }
        return windows.contains { window in
            window[kCGWindowOwnerPID as String] as? pid_t == pid
                && (window[kCGWindowLayer as String] as? Int ?? 0) > Int(CGWindowLevelForKey(.modalPanelWindow))
        }
    }

    /// The process owning the frontmost window under a point given in global top-left coordinates.
    static func windowOwner(at point: CGPoint) -> pid_t? {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windows = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else { return nil }
        for window in windows {
            guard let boundsDict = window[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsDict), bounds.contains(point) else { continue }
            return window[kCGWindowOwnerPID as String] as? pid_t
        }
        return nil
    }
}
