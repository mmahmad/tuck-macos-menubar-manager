import ApplicationServices
import Cocoa

/// One icon in the right-hand side of the menu bar, as reported by its owning app's accessibility tree.
final class MenuBarItem {
    enum Visibility { case hidden, notch, visible }

    let element: AXUIElement
    let pid: pid_t
    let appName: String
    let bundleID: String?
    let icon: NSImage?
    /// Title / description / identifier the app exposes for the item, if any.
    let detail: String?
    let frame: CGRect

    var isApple: Bool { bundleID?.hasPrefix("com.apple.") ?? false }

    init(element: AXUIElement, app: NSRunningApplication, detail: String?, frame: CGRect) {
        self.element = element
        self.pid = app.processIdentifier
        self.appName = app.localizedName ?? app.bundleIdentifier ?? "Unknown"
        self.bundleID = app.bundleIdentifier
        self.icon = app.icon
        self.detail = detail
        self.frame = frame
    }

    func visibility(on screen: NSScreen?) -> Visibility {
        Self.visibility(of: frame, on: screen)
    }

    static func visibility(of frame: CGRect, on screen: NSScreen?) -> Visibility {
        guard let screen else { return .visible }
        if frame.minX < screen.frame.minX { return .hidden }
        // Overflowing items are parked under the notch instead of being drawn.
        if let right = screen.auxiliaryTopRightArea, frame.minX < right.minX { return .notch }
        return .visible
    }
}

enum AX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        guard let s = value(element, attribute) as? String, !s.isEmpty else { return nil }
        return s
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let v = value(element, attribute), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func frame(_ element: AXUIElement) -> CGRect? {
        guard let p = value(element, kAXPositionAttribute), let s = value(element, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(s) == AXValueGetTypeID() else { return nil }
        var origin = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(p as! AXValue, .cgPoint, &origin)
        AXValueGetValue(s as! AXValue, .cgSize, &size)
        return CGRect(origin: origin, size: size)
    }
}

final class MenuBarScanner {
    private(set) var items: [MenuBarItem] = []
    private let queue = DispatchQueue(label: "tuck.scanner")

    /// Rescans in the background and calls `completion` on the main queue.
    func refresh(completion: @escaping () -> Void) {
        let apps = NSWorkspace.shared.runningApplications
        queue.async {
            let scanned = Self.scan(apps)
            DispatchQueue.main.async {
                self.items = scanned
                completion()
            }
        }
    }

    func refreshSynchronously() {
        items = Self.scan(NSWorkspace.shared.runningApplications)
    }

    private static func scan(_ apps: [NSRunningApplication]) -> [MenuBarItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        let lock = NSLock()
        var found: [MenuBarItem] = []

        DispatchQueue.concurrentPerform(iterations: apps.count) { index in
            let app = apps[index]
            guard app.processIdentifier != ownPID, !app.isTerminated else { return }
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            // A hung app must not stall the whole scan.
            AXUIElementSetMessagingTimeout(appElement, 0.4)
            guard let bar = AX.element(appElement, "AXExtrasMenuBar"),
                  let children = AX.value(bar, kAXChildrenAttribute) as? [AXUIElement] else { return }

            let items = children.compactMap { child -> MenuBarItem? in
                guard let frame = AX.frame(child), frame.width > 0 else { return nil }
                let detail = AX.string(child, kAXTitleAttribute)
                    ?? AX.string(child, kAXDescriptionAttribute)
                    ?? AX.string(child, kAXIdentifierAttribute)
                return MenuBarItem(element: child, app: app, detail: detail, frame: frame)
            }
            lock.lock()
            found.append(contentsOf: items)
            lock.unlock()
        }
        // Control Center reports a nameless twin for some third-party items; keep the app's own entry.
        let thirdPartyFrames = found.filter { !$0.isApple }.map(\.frame)
        found.removeAll { item in item.isApple && thirdPartyFrames.contains { abs($0.midX - item.frame.midX) < 2 } }
        // Right-to-left, the order the eye reads the status area from the clock inwards.
        return found.sorted { $0.frame.minX > $1.frame.minX }
    }
}
