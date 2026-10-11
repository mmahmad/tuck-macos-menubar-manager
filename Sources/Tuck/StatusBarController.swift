import Cocoa

/// Owns Tuck's two status items: the main icon with the search panel, and the separator that
/// hides everything to its left by growing wide enough to push it off screen.
final class StatusBarController: NSObject {
    private static let expandedLength: CGFloat = 12
    private static let collapsedLength: CGFloat = 10_000
    private static let mainName = "TuckMain"
    private static let separatorName = "TuckSeparator"

    /// An item pulled out of the hidden section because the user opened it from the panel.
    private struct ShownItem {
        let element: AXUIElement
        let pid: pid_t
        var timer: Timer?
    }

    private let scanner = MenuBarScanner()
    private let model = PanelModel()
    private let panel: PanelController
    private let mainItem: NSStatusItem
    private let separator: NSStatusItem
    /// Moves replay mouse events, so they must never interleave.
    private let moveQueue = DispatchQueue(label: "tuck.mover")
    private var shownItems: [ShownItem] = []
    private var rehideMonitor: Any?

    private var screen: NSScreen? { mainItem.button?.window?.screen ?? NSScreen.screens.first }

    override init() {
        Self.seedPositionsIfNeeded(using: scanner)
        panel = PanelController(model: model)
        // The main icon is created first so it ends up to the right of the separator.
        mainItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        mainItem.autosaveName = Self.mainName
        separator = NSStatusBar.system.statusItem(withLength: Self.expandedLength)
        separator.autosaveName = Self.separatorName
        super.init()

        if let button = mainItem.button {
            button.image = NSImage(systemSymbolName: "menubar.rectangle", accessibilityDescription: "Tuck")
            if button.image == nil { button.title = "≡" }
            button.target = self
            button.action = #selector(togglePanel)
            button.sendAction(on: [.leftMouseDown, .rightMouseDown])
        }
        if let button = separator.button {
            button.title = "│"
            button.alphaValue = 0.4
            button.target = self
            button.action = #selector(toggleCollapsed)
            button.toolTip = "Items to the left of this line are hidden by Tuck. ⌘-drag icons across it."
        }

        model.collapsed = Settings.collapsed
        model.onActivate = { [weak self] item, forceClick in
            self?.panel.close()
            self?.open(item, forceClick: forceClick)
        }
        model.onToggleCollapsed = { [weak self] in
            self?.panel.close()
            self?.toggleCollapsed()
        }

        // Status item windows are positioned asynchronously, so collapse once they have settled.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.applyCollapsed()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.rescan() }
        }
    }

    /// On first launch, puts the separator just right of the right-most third-party icon so that
    /// every third-party icon starts out hidden. macOS stores a status item's position as its
    /// distance from the right edge of the screen.
    private static func seedPositionsIfNeeded(using scanner: MenuBarScanner) {
        let defaults = UserDefaults.standard
        let separatorKey = "NSStatusItem Preferred Position \(separatorName)"
        guard defaults.object(forKey: separatorKey) == nil else { return }

        scanner.refreshSynchronously()
        var position: CGFloat = 400
        if let screen = NSScreen.screens.first,
           let rightmost = scanner.items.filter({ !$0.isApple }).map(\.frame.maxX).max() {
            position = max(screen.frame.maxX - rightmost, 4)
        }
        defaults.set(position - 1, forKey: separatorKey)
        defaults.set(position - 2, forKey: "NSStatusItem Preferred Position \(mainName)")
    }

    // MARK: - Hiding

    private func setSeparatorCollapsed(_ collapse: Bool) {
        separator.length = collapse ? Self.collapsedLength : Self.expandedLength
    }

    private func applyCollapsed() {
        defer { model.collapsed = Settings.collapsed }
        guard Settings.collapsed else { return setSeparatorCollapsed(false) }
        // Growing a separator that sits right of the main icon would push Tuck itself off screen.
        if let main = mainItem.button?.window?.frame, let sep = separator.button?.window?.frame, sep.minX > main.minX {
            Settings.collapsed = false
            setSeparatorCollapsed(false)
            NSSound.beep()
            return
        }
        setSeparatorCollapsed(true)
    }

    @objc private func toggleCollapsed() {
        disarmRehide()
        Settings.collapsed.toggle()
        applyCollapsed()
    }

    // MARK: - Panel

    @objc private func togglePanel() {
        if panel.isVisible { return panel.close() }
        guard let anchor = mainItem.button?.window?.frame else { return }
        model.screen = screen
        model.items = scanner.items
        panel.show(below: anchor, on: screen)
        rescan()
    }

    private func rescan(rescuingSystemItems: Bool = true) {
        scanner.refresh {
            self.model.screen = self.screen
            self.model.items = self.scanner.items
            self.logDiagnostics()
            if rescuingSystemItems { self.rescueSystemItems() }
        }
    }

    /// Wi-Fi, Sound and friends that ended up left of the separator are moved back out next to Tuck.
    private func rescueSystemItems() {
        guard Settings.keepSystemItemsVisible else { return }
        let screen = self.screen
        // Right-most first: each one lands directly right of Tuck, which preserves their order.
        let stranded = scanner.items.filter { $0.isApple && $0.visibility(on: screen) == .hidden }
        guard !stranded.isEmpty else { return }
        moveQueue.async {
            for item in stranded { _ = self.relocate(item.element, toVisibleSide: true) }
            DispatchQueue.main.async { self.rescan(rescuingSystemItems: false) }
        }
    }

    // MARK: - Moving items

    /// Moves an item across the separator and confirms it arrived. Must run on `moveQueue`.
    private func relocate(_ element: AXUIElement, toVisibleSide: Bool) -> Bool {
        func arrived() -> (done: Bool, frame: CGRect, main: CGRect, separator: CGRect)? {
            guard let frame = AX.frame(element) else { return nil }
            let frames = DispatchQueue.main.sync {
                (self.mainItem.button?.window?.frame, self.separator.button?.window?.frame, self.screen)
            }
            guard let main = frames.0, let sep = frames.1 else { return nil }
            let done = toVisibleSide
                ? MenuBarItem.visibility(of: frame, on: frames.2) == .visible
                : frame.midX < sep.minX
            return (done, frame, main, sep)
        }

        for _ in 0..<3 {
            guard let state = arrived() else { return false }
            if state.done { return true }
            guard Mover.move(itemAt: state.frame, to: toVisibleSide ? .rightOf(state.main) : .leftOf(state.separator)) else { return false }
            usleep(300_000)
        }
        return arrived()?.done ?? false
    }

    // MARK: - Opening items

    private func open(_ item: MenuBarItem, forceClick: Bool) {
        if item.visibility(on: screen) == .visible {
            // Opening an item that is already out on loan restarts its countdown.
            if shownItems.contains(where: { CFEqual($0.element, item.element) }) { scheduleReturn(of: item) }
            Activator.press(item, forceClick: forceClick)
            return
        }
        // A tucked-away item's menu would open off screen, so put just that icon on the menu bar first.
        moveQueue.async {
            let moved = self.relocate(item.element, toVisibleSide: true)
            DispatchQueue.main.async {
                if moved {
                    self.scheduleReturn(of: item)
                    Activator.press(item, forceClick: forceClick)
                } else {
                    self.openByRevealingEverything(item, forceClick: forceClick)
                }
            }
        }
    }

    private func scheduleReturn(of item: MenuBarItem) {
        if let index = shownItems.firstIndex(where: { CFEqual($0.element, item.element) }) {
            shownItems[index].timer?.invalidate()
            shownItems.remove(at: index)
        }
        let duration = Settings.showDuration
        guard duration > 0 else { return }
        let element = item.element
        let timer = Timer.scheduledTimer(withTimeInterval: duration, repeats: false) { [weak self] _ in
            self?.returnItem(element)
        }
        shownItems.append(ShownItem(element: element, pid: item.pid, timer: timer))
    }

    private func returnItem(_ element: AXUIElement) {
        guard let index = shownItems.firstIndex(where: { CFEqual($0.element, element) }) else { return }
        // Pulling the icon away from under an open menu or popover would be rude; check back shortly.
        if Activator.hasOpenMenu(pid: shownItems[index].pid) {
            shownItems[index].timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: false) { [weak self] _ in
                self?.returnItem(element)
            }
            return
        }
        shownItems.remove(at: index)
        moveQueue.async { _ = self.relocate(element, toVisibleSide: false) }
    }

    /// Puts every item that is out on loan back before Tuck quits, so nothing is left stranded.
    func returnShownItemsNow() {
        guard let sep = separator.button?.window?.frame else { return }
        for shown in shownItems {
            shown.timer?.invalidate()
            if let frame = AX.frame(shown.element) {
                Mover.move(itemAt: frame, to: .leftOf(sep))
                usleep(200_000)
            }
        }
        shownItems.removeAll()
    }

    /// Fallback for items that refuse to be moved: show the whole hidden section while the item is in use.
    private func openByRevealingEverything(_ item: MenuBarItem, forceClick: Bool) {
        setSeparatorCollapsed(false)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            Activator.press(item, forceClick: forceClick)
            self.armRehide(ignoringClicksIn: item.pid)
        }
    }

    /// Hides the section again on the next click that lands outside the opened app's own menu or popover.
    private func armRehide(ignoringClicksIn pid: pid_t) {
        disarmRehide()
        let armedAt = Date()
        rehideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, Date().timeIntervalSince(armedAt) > 0.5 else { return }
            if let location = CGEvent(source: nil)?.location, Activator.windowOwner(at: location) == pid { return }
            self.disarmRehide()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { self.applyCollapsed() }
        }
    }

    private func disarmRehide() {
        if let rehideMonitor { NSEvent.removeMonitor(rehideMonitor) }
        rehideMonitor = nil
    }

    // MARK: - Misc

    /// With `-debug YES` on the command line, writes what the scanner sees to ~/Library/Logs/Tuck.log.
    private func logDiagnostics() {
        guard UserDefaults.standard.bool(forKey: "debug") else { return }
        var lines = ["--- \(Date())  collapsed=\(Settings.collapsed) onLoan=\(shownItems.count)"]
        lines.append("main=\(mainItem.button?.window?.frame ?? .zero) separator=\(separator.button?.window?.frame ?? .zero)")
        for item in scanner.items {
            lines.append("\(item.visibility(on: screen)) x=\(Int(item.frame.minX)) w=\(Int(item.frame.width)) \(item.bundleID ?? item.appName) [\(item.detail ?? "-")]")
        }
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/Tuck.log")
        let text = lines.joined(separator: "\n") + "\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(text.utf8))
            try? handle.close()
        } else {
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}
