import AppCore
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            OnboardingBanner(state: model.onboarding)
            if let problem = model.engineProblem {
                Banner(text: problem)
            }
            if model.mice.count > 1 {
                Picker("Settings apply to", selection: Binding(get: { model.selectedMouse ?? model.mice[0].id },
                                                               set: { model.select($0) })) {
                    ForEach(Array(model.mice.enumerated()), id: \.element.id) { i, mouse in
                        Text(MouseLabel.text(mouse, index: i)).tag(mouse.id)
                    }
                }
                .fixedSize()
                .padding([.horizontal, .top])
            }
            if model.karabinerConflict {
                Banner(text: "Karabiner-Elements is modifying the Pro Click Mini, so tilts can't be detected. "
                    + "In Karabiner › Devices, turn off “Modify events” for Pro Click Mini.")
            }
            TabView {
                CustomizeTab(model: model).tabItem { Text("Customize") }
                PerformanceTab(model: model).tabItem { Text("Performance") }
                PowerTab(model: model).tabItem { Text("Power") }
            }
            .padding()
        }
        .frame(width: 620, height: 460)
    }
}

struct Banner: View {
    let text: String
    var action: (title: String, run: () -> Void)?

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.yellow)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            if let action { Button(action.title, action: action.run) }
        }
        .padding(10)
        .background(.yellow.opacity(0.15))
    }
}

struct OnboardingBanner: View {
    let state: OnboardingState

    var body: some View {
        switch state {
        case .ready:
            EmptyView()
        case .needsBluetooth:
            Banner(text: "ProClick Mini needs Bluetooth access to read and change the mouse's settings.",
                   action: ("Open Settings", { Permissions.openSettings("Privacy_Bluetooth") }))
        case .bluetoothOff:
            Banner(text: "Bluetooth is off. Turn it on to connect to the Pro Click Mini.")
        case .needsAccessibility:
            Banner(text: "Allow ProClick Mini in Accessibility so wheel tilts can switch desktops.",
                   action: ("Open Settings", { Permissions.openSettings("Privacy_Accessibility") }))
        case .needsInputMonitoring:
            Banner(text: "Allow ProClick Mini in Input Monitoring so it can recognize the mouse's buttons.",
                   action: ("Open Settings", { Permissions.openSettings("Privacy_ListenEvent") }))
        }
    }
}
