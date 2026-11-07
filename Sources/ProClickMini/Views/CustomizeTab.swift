import AppCore
import InputEngine
import SwiftUI

struct CustomizeTab: View {
    @ObservedObject var model: AppModel
    @State private var selection: ButtonID?

    var body: some View {
        HStack(alignment: .top, spacing: 24) {
            MouseDiagram(selection: $selection)
                .padding(.top, 8)
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leading, verticalSpacing: 6) {
                    ForEach(ButtonID.allCases, id: \.self) { id in
                        GridRow {
                            Text(id.title)
                                .fontWeight(selection == id ? .semibold : .regular)
                            Button(ActionCatalog.title(model.mapping.action(for: id), for: id)) {
                                selection = id
                            }
                            .popover(isPresented: Binding(get: { selection == id },
                                                          set: { if !$0 { selection = nil } })) {
                                ActionPicker(button: id, current: model.mapping.action(for: id)) { action in
                                    model.setAction(action, for: id)
                                    selection = nil
                                }
                            }
                        }
                    }
                }
                Divider()
                Picker("Desktop switching", selection: $model.spaceMethod) {
                    Text("Swipe animation").tag(SpaceMethod.dockSwipe)
                    Text("Keyboard (⌃← / ⌃→)").tag(SpaceMethod.controlArrow)
                }
                .help("Keyboard mode needs “Move left/right a space” on in Keyboard Shortcuts › Mission Control.")
                Text("In Safari and Finder, side buttons left on Default send ⌘[ / ⌘], since those apps ignore them.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Reset to Defaults") { model.resetMapping() }
                        .disabled(model.mapping == .default)
                }
            }
        }
        .padding()
    }
}

struct ActionPicker: View {
    let button: ButtonID
    let current: Action
    let choose: (Action) -> Void
    @State private var recording = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                row(.passThrough)
                row(.disabled)
                ForEach(ActionCatalog.groups, id: \.title) { group in
                    Text(group.title).font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                    ForEach(group.actions.indices, id: \.self) { i in row(group.actions[i]) }
                }
                Text("Keyboard shortcut").font(.caption).foregroundStyle(.secondary).padding(.top, 6)
                if case .shortcut = current { row(current) }
                if recording {
                    ShortcutRecorder(onRecord: { choose($0) }, onCancel: { recording = false })
                } else {
                    Button("Record shortcut…") { recording = true }
                }
                if button == .left, current == .passThrough {
                    Text("Remapping the left button leaves this mouse without a left click.")
                        .font(.caption).foregroundStyle(.orange).padding(.top, 6)
                }
            }
            .padding(12)
        }
        .frame(width: 260, height: 420)
    }

    private func row(_ action: Action) -> some View {
        Button {
            choose(action)
        } label: {
            HStack {
                Image(systemName: "checkmark").opacity(action == current ? 1 : 0)
                Text(ActionCatalog.title(action, for: button))
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }
}

/// Captures the next key press (with modifiers) through a local event monitor. Esc cancels.
struct ShortcutRecorder: View {
    let onRecord: (Action) -> Void
    let onCancel: () -> Void
    @State private var monitor: Any?

    var body: some View {
        Text("Press a shortcut… (Esc to cancel)")
            .padding(6)
            .background(RoundedRectangle(cornerRadius: 5).stroke(Color.accentColor))
            .onAppear {
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                    let mods = event.modifierFlags.intersection([.command, .option, .control, .shift])
                    if event.keyCode == 53 && mods.isEmpty {
                        onCancel()
                    } else {
                        onRecord(.shortcut(keyCode: event.keyCode, modifiers: UInt64(mods.rawValue)))
                    }
                    return nil
                }
            }
            .onDisappear {
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            }
    }
}
