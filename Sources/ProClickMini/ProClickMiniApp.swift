import AppCore
import SwiftUI

@main
struct ProClickMiniApp: App {
    @StateObject private var model: AppModel

    init() {
        let model = AppModel()
        model.start()
        _model = StateObject(wrappedValue: model)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(model: model)
        } label: {
            Label(model.batteryPercent.map { "\($0)%" } ?? "", systemImage: "computermouse")
                .labelStyle(.titleAndIcon)
        }
        Window("ProClick Mini", id: "settings") {
            SettingsView(model: model)
        }
        .windowResizability(.contentSize)
    }
}
