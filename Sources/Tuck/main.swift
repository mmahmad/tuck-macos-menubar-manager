import ApplicationServices
import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: StatusBarController?
    private var trustTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Settings.registerDefaults()
        // Reading and pressing other apps' menu bar items both go through the accessibility API.
        let prompt = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(prompt) {
            controller = StatusBarController()
            return
        }
        trustTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            guard AXIsProcessTrusted() else { return }
            timer.invalidate()
            self?.controller = StatusBarController()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        controller?.returnShownItemsNow()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
