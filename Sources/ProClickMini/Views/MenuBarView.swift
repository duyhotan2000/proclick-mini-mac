import AppCore
import RazerBLE
import SwiftUI

struct MenuBarView: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if model.needsAttention {
            Button("⚠︎ Tilt switching needs attention — Open Settings…") { openSettings() }
        }
        Text(statusText)
        if model.mice.count > 1 {
            Picker("Mouse", selection: Binding(get: { model.selectedMouse ?? model.mice[0].id },
                                               set: { model.select($0) })) {
                ForEach(Array(model.mice.enumerated()), id: \.element.id) { i, mouse in
                    Text(MouseLabel.text(mouse, index: i)).tag(mouse.id)
                }
            }
        }
        if let state = model.state {
            Picker("DPI", selection: dpiBinding(state)) {
                ForEach(Array(state.dpi.stages.enumerated()), id: \.offset) { i, stage in
                    Text("\(stage.x) DPI").tag(i)
                }
            }
            .disabled(model.isWriting)
        }
        Divider()
        Button("Open Settings…") { openSettings() }
        .keyboardShortcut(",")
        Toggle("Launch at Login", isOn: Binding(
            get: { model.launchAtLogin },
            set: { try? model.setLaunchAtLogin($0) }))
        Divider()
        Button("Quit ProClick Mini") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func openSettings() {
        openWindow(id: "settings")
        NSApp.activate(ignoringOtherApps: true)
    }

    private var statusText: String {
        switch model.connection {
        case .connected(let name):
            model.batteryPercent.map { "\(name) — battery \($0)%" } ?? "\(name) — connected"
        case .disconnected: "Pro Click Mini — disconnected"
        case .searching: "Pro Click Mini — searching…"
        }
    }

    private func dpiBinding(_ state: MouseState) -> Binding<Int> {
        Binding(
            get: { state.dpi.activeIndex },
            set: { index in
                var s = state
                s.dpi.activeID = s.dpi.stages[index].id
                Task { await model.apply(s) }
            })
    }
}

/// Pro Click Minis all report the same name, so number them and add a short id.
enum MouseLabel {
    static func text(_ mouse: MouseInfo, index: Int) -> String {
        "Pro Click Mini \(index + 1) (\(mouse.id.uuidString.prefix(4)))"
    }
}
