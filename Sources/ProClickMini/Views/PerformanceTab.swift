import AppCore
import RazerBLE
import SwiftUI

struct PerformanceTab: View {
    @ObservedObject var model: AppModel
    @State private var stages: [UInt16] = []
    @State private var active = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.state == nil {
                Text(model.connection == .searching ? "Looking for the mouse…" : "Connect the mouse to change DPI.")
                    .foregroundStyle(.secondary)
            } else {
                Text("DPI stages").font(.headline)
                ForEach(stages.indices, id: \.self) { i in
                    HStack {
                        Button {
                            active = i
                        } label: {
                            Image(systemName: active == i ? "largecircle.fill.circle" : "circle")
                        }
                        .buttonStyle(.plain)
                        .help("Active stage")
                        Text("Stage \(i + 1)").frame(width: 60, alignment: .leading)
                        Slider(value: dpiBinding(i), in: Double(Limits.dpiRange.lowerBound)...Double(Limits.dpiRange.upperBound),
                               step: Double(Limits.dpiStep))
                        Stepper(value: dpiBinding(i), in: Double(Limits.dpiRange.lowerBound)...Double(Limits.dpiRange.upperBound),
                                step: Double(Limits.dpiStep)) {
                            Text("\(stages[i]) DPI").monospacedDigit().frame(width: 80, alignment: .trailing)
                        }
                    }
                }
                HStack {
                    Button("Add Stage") {
                        stages.append(min((stages.last ?? 800) + 400, Limits.dpiRange.upperBound))
                    }
                    .disabled(stages.count >= Limits.stageCount.upperBound)
                    Button("Remove Stage") {
                        stages.removeLast()
                        active = min(active, stages.count - 1)
                    }
                    .disabled(stages.count <= Limits.stageCount.lowerBound)
                    Spacer()
                    Button("Revert") { load() }.disabled(!isDirty)
                    Button("Apply") { apply() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isDirty || model.isWriting)
                }
                OutcomeView(model: model)
            }
            Spacer()
            Text("Polling rate can't be changed over Bluetooth.").font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .onAppear(perform: load)
        .onChange(of: model.state) { load() }
    }

    private var isDirty: Bool {
        guard let s = model.state else { return false }
        return stages != s.dpi.stages.map(\.x) || active != s.dpi.activeIndex
    }

    private func load() {
        guard let s = model.state else { return }
        stages = s.dpi.stages.map(\.x)
        active = s.dpi.activeIndex
    }

    private func dpiBinding(_ i: Int) -> Binding<Double> {
        Binding(get: { Double(stages[i]) },
                set: { stages[i] = UInt16(($0 / Double(Limits.dpiStep)).rounded()) * Limits.dpiStep })
    }

    private func apply() {
        guard var s = model.state else { return }
        // Ids 1…n here; the model maps them onto the ids the mouse uses.
        s.dpi.stages = stages.enumerated().map { DPIStage(id: UInt8($0.offset + 1), x: $0.element, y: $0.element) }
        s.dpi.activeID = UInt8(active + 1)
        Task { await model.apply(s) }
    }
}
