import AppKit
import SwiftUI

struct AboutView: View {
    static let repo = URL(string: "https://github.com/duyhotan2000/proclick-mini-mac")!

    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 96, height: 96)
            Text("ProClick Mini")
                .font(.title2.bold())
            Text("Version \(Self.version)")
                .foregroundStyle(.secondary)
            Text("Configure the Razer Pro Click Mini over Bluetooth, and switch desktops by tilting the scroll wheel.")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Link("github.com/duyhotan2000/proclick-mini-mac", destination: Self.repo)
            Divider()
            Text("© 2026 Ho Tan Duy. MIT License.")
            Text("Desktop-swipe gesture adapted from Mac Mouse Fix by Noah Nuebling (MMF License).")
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text("Not affiliated with or endorsed by Razer Inc.")
        }
        .font(.callout)
        .padding(24)
        .frame(width: 340)
    }

    static var version: String {
        let info = Bundle.main.infoDictionary
        guard let short = info?["CFBundleShortVersionString"] as? String else { return "dev" }
        return info?["CFBundleVersion"].map { "\(short) (\($0))" } ?? short
    }
}

/// Replaces the standard About menu item so it opens our About window.
struct AboutCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("About ProClick Mini") { openWindow(id: "about") }
    }
}
