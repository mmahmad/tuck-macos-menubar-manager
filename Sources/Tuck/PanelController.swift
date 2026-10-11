import Cocoa
import Combine
import SwiftUI

/// A borderless panel that can take keyboard focus without activating Tuck, so the search field
/// works while the user's current app stays frontmost.
private final class KeyPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class PanelController: NSObject, NSWindowDelegate {
    private let model: PanelModel
    private let panel: KeyPanel
    private let hosting: NSHostingView<PanelView>
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var subscription: AnyCancellable?
    private var topLeft = CGPoint.zero

    var isVisible: Bool { panel.isVisible }

    init(model: PanelModel) {
        self.model = model
        panel = KeyPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        hosting = NSHostingView(rootView: PanelView(model: model))
        super.init()

        let background = NSVisualEffectView()
        background.material = .menu
        background.blendingMode = .behindWindow
        background.state = .active
        background.wantsLayer = true
        background.layer?.cornerRadius = 12
        background.layer?.masksToBounds = true
        hosting.sizingOptions = [.intrinsicContentSize]
        hosting.autoresizingMask = [.width, .height]
        background.addSubview(hosting)

        panel.contentView = background
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self

        // The list grows and shrinks with the search results; keep the panel hugging it.
        subscription = model.objectWillChange.sink { [weak self] in
            DispatchQueue.main.async { self?.resize() }
        }
    }

    func show(below anchor: NSRect, on screen: NSScreen?) {
        model.query = ""
        model.presentation += 1
        let width = hosting.fittingSize.width
        let maxX = (screen?.visibleFrame.maxX ?? anchor.maxX) - 8
        topLeft = CGPoint(x: min(anchor.minX, maxX - width), y: anchor.minY - 4)
        resize()
        panel.makeKeyAndOrderFront(nil)

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            switch event.keyCode {
            case 125: self.model.moveSelection(by: 1)
            case 126: self.model.moveSelection(by: -1)
            case 36, 76: self.model.activateSelection(forceClick: event.modifierFlags.contains(.option))
            case 53: self.close()
            default: return event
            }
            return nil
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.close()
        }
    }

    func close() {
        guard panel.isVisible else { return }
        for monitor in [keyMonitor, clickMonitor] {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
        keyMonitor = nil
        clickMonitor = nil
        panel.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        close()
    }

    private func resize() {
        hosting.layoutSubtreeIfNeeded()
        let size = hosting.fittingSize
        panel.setFrame(NSRect(x: topLeft.x, y: topLeft.y - size.height, width: size.width, height: size.height), display: true)
        panel.invalidateShadow()
    }
}
