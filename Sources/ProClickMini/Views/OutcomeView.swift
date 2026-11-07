import AppCore
import RazerBLE
import SwiftUI

/// Result of the last write to the mouse, with recovery buttons when restoring failed.
struct OutcomeView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.isWriting {
            HStack { ProgressView().controlSize(.small); Text("Writing to mouse…") }
        } else if let outcome = model.lastOutcome {
            switch outcome {
            case .applied:
                Label("Saved to mouse", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
            case .notApplied(let reason):
                Label("Not changed: \(reason)", systemImage: "exclamationmark.circle").foregroundStyle(.orange)
            case .rolledBack(let reason, _):
                Label("\(reason) Previous settings restored.", systemImage: "arrow.uturn.backward.circle")
                    .foregroundStyle(.orange)
            case .rollbackFailed(let reason, let snapshot):
                VStack(alignment: .leading, spacing: 6) {
                    Label(reason, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
                    Text("Backup of your previous settings: \(snapshot.path)")
                        .font(.caption).textSelection(.enabled)
                    HStack {
                        Button("Restore My Original Settings") { Task { await model.restoreOriginal() } }
                        Button("Restore Factory Defaults") { Task { await model.restoreFactory() } }
                    }
                }
            }
        }
    }
}
