import Foundation

enum Settings {
    static let collapsedKey = "collapsed"
    static let showDurationKey = "showDuration"
    static let keepSystemItemsVisibleKey = "keepSystemItemsVisible"
    static let defaultShowDuration: Double = 30

    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            collapsedKey: true,
            showDurationKey: defaultShowDuration,
            keepSystemItemsVisibleKey: true,
        ])
    }

    static var collapsed: Bool {
        get { UserDefaults.standard.bool(forKey: collapsedKey) }
        set { UserDefaults.standard.set(newValue, forKey: collapsedKey) }
    }

    /// Seconds an item opened from the panel stays on the menu bar; 0 leaves it there.
    static var showDuration: Double { UserDefaults.standard.double(forKey: showDurationKey) }
    static var keepSystemItemsVisible: Bool { UserDefaults.standard.bool(forKey: keepSystemItemsVisibleKey) }
}
