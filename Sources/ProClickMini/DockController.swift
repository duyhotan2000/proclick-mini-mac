import AppCore
import AppKit

/// Switches between a menu-bar-only app and a regular Dock app as windows open and close.
/// Tracks AppKit window notifications: SwiftUI's onDisappear doesn't fire reliably when a
/// `Window` scene is closed.
@MainActor
final class DockController {
    static let shared = DockController()
    private var presence = DockPresence()
    private var observers: [NSObjectProtocol] = []

    func start() {
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated { if let key = Self.key(window) { self.update { $0.opened(key) } } }
            },
            center.addObserver(forName: NSWindow.willCloseNotification, object: nil, queue: .main) { note in
                let window = note.object as? NSWindow
                MainActor.assumeIsolated { if let key = Self.key(window) { self.update { $0.closed(key) } } }
            },
        ]
    }

    /// Our titled windows (Settings, About); the menu-bar menu and status item aren't titled.
    private static func key(_ window: NSWindow?) -> String? {
        guard let window, window.styleMask.contains(.titled) else { return nil }
        return String(describing: ObjectIdentifier(window))
    }

    private func update(_ change: (inout DockPresence) -> Void) {
        let before = presence.showsInDock
        change(&presence)
        guard presence.showsInDock != before else { return }
        NSApp.setActivationPolicy(presence.showsInDock ? .regular : .accessory)
        if presence.showsInDock { NSApp.activate(ignoringOtherApps: true) }
    }
}
