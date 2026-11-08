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
            Image(systemName: "computermouse")
        }
        Window("ProClick Mini", id: "settings") {
            SettingsView(model: model)
                .showsInDock("settings")
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appInfo) { AboutCommand() }
        }
        Window("About ProClick Mini", id: "about") {
            AboutView()
                .showsInDock("about")
        }
        .windowResizability(.contentSize)
    }
}
