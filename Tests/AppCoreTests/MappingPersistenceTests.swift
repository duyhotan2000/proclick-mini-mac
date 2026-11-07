import Foundation
import InputEngine
import Testing
@testable import AppCore

private func freshDefaults() -> UserDefaults {
    let name = "ProClickMiniTests-\(UUID())"
    let d = UserDefaults(suiteName: name)!
    d.removePersistentDomain(forName: name)
    return d
}

@MainActor @Test func mappingPersistsAcrossModels() {
    let defaults = freshDefaults()
    AppModel(defaults: defaults).setAction(.missionControl, for: .button5)
    #expect(AppModel(defaults: defaults).mapping.action(for: .button5) == .missionControl)
}

@MainActor @Test func corruptMappingFallsBackToDefault() {
    let defaults = freshDefaults()
    defaults.set(Data("not json".utf8), forKey: "mapping.v1")
    #expect(AppModel(defaults: defaults).mapping == .default)
}

@MainActor @Test func resetMappingRestoresDefaultAndPersists() {
    let defaults = freshDefaults()
    let model = AppModel(defaults: defaults)
    model.setAction(.missionControl, for: .button5)
    model.resetMapping()
    #expect(model.mapping == .default)
    #expect(AppModel(defaults: defaults).mapping == .default)
}

@MainActor @Test func spaceMethodPersists() {
    let defaults = freshDefaults()
    AppModel(defaults: defaults).spaceMethod = .controlArrow
    #expect(AppModel(defaults: defaults).spaceMethod == .controlArrow)
}

@MainActor @Test func batteryClearsWhenMouseDisconnects() async {
    let model = AppModel(defaults: freshDefaults())
    model.batteryChanged(50)
    await model.connectionChanged(.disconnected)
    #expect(model.batteryPercent == nil)
    #expect(model.state == nil)
}
