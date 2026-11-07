import AppCore
import SwiftUI

struct PowerTab: View {
    @ObservedObject var model: AppModel
    @State private var confirm: Restore?

    enum Restore: Identifiable {
        case original, factory
        var id: Self { self }
    }

    static let sleepChoices: [(seconds: UInt16, title: String)] = [
        (60, "1 minute"), (120, "2 minutes"), (180, "3 minutes"), (300, "5 minutes"), (600, "10 minutes"),
        (900, "15 minutes"),
    ]

    var body: some View {
        Form {
            Section("Battery") {
                LabeledContent("Level", value: model.batteryPercent.map { "\($0)%" } ?? "—")
                LabeledContent("Type", value: "AA battery (not rechargeable)")
                Toggle("Notify me when the battery drops to 15%", isOn: $model.lowBatteryAlerts)
            }
            Section("Sleep") {
                Picker("Sleep after inactivity", selection: sleepBinding) {
                    if let s = model.state, !Self.sleepChoices.contains(where: { $0.seconds == s.sleepSeconds }) {
                        Text("\(s.sleepSeconds) seconds").tag(s.sleepSeconds)
                    }
                    ForEach(Self.sleepChoices, id: \.seconds) { Text($0.title).tag($0.seconds) }
                }
                .disabled(model.state == nil || model.isWriting)
                OutcomeView(model: model)
            }
            Section {
                Menu("Reset Mouse Settings…") {
                    Button("Restore My Original Settings…") { confirm = .original }
                    Button("Restore Factory Defaults…") { confirm = .factory }
                }
                .fixedSize()
                .disabled(model.state == nil || model.isWriting)
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(confirmTitle, isPresented: Binding(get: { confirm != nil }, set: { if !$0 { confirm = nil } }),
                            presenting: confirm) { which in
            Button(which == .original ? "Restore Original" : "Restore Factory Defaults", role: .destructive) {
                Task { which == .original ? await model.restoreOriginal() : await model.restoreFactory() }
            }
        } message: { which in
            Text(which == .original
                 ? "Writes back the DPI stages (400/800/1600/3200/6400, 3200 active) and 5-minute sleep timer this mouse had on 2026-11-06."
                 : "Writes Razer's factory defaults: 1600 DPI active, 5-minute sleep timer.")
        }
    }

    private var confirmTitle: String {
        confirm == .factory ? "Restore factory defaults?" : "Restore your original settings?"
    }

    private var sleepBinding: Binding<UInt16> {
        Binding(get: { model.state?.sleepSeconds ?? 300 },
                set: { seconds in
                    guard var s = model.state, s.sleepSeconds != seconds else { return }
                    s.sleepSeconds = seconds
                    Task { await model.apply(s) }
                })
    }
}
