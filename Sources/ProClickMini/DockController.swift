import AppCore
import AppKit
import SwiftUI

/// Switches between a menu-bar-only app and a regular Dock app as windows open and close.
@MainActor
final class DockController {
    static let shared = DockController()
    private var presence = DockPresence()

    func opened(_ window: String) {
        presence.opened(window)
        apply()
        NSApp.activate(ignoringOtherApps: true)
    }

    func closed(_ window: String) {
        presence.closed(window)
        apply()
    }

    private func apply() {
        NSApp.setActivationPolicy(presence.showsInDock ? .regular : .accessory)
    }
}

extension View {
    /// Shows the Dock icon while this window is open.
    func showsInDock(_ window: String) -> some View {
        onAppear { DockController.shared.opened(window) }
            .onDisappear { DockController.shared.closed(window) }
    }
}
