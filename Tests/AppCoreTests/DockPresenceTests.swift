import Testing
@testable import AppCore

@Test func hiddenFromDockWithNoWindows() {
    #expect(!DockPresence().showsInDock)
}

@Test func showsInDockWhileAnyWindowIsOpen() {
    var d = DockPresence()
    d.opened("settings")
    d.opened("about")
    d.closed("settings")
    #expect(d.showsInDock)
    d.closed("about")
    #expect(!d.showsInDock)
}

@Test func repeatedOpenNeedsOnlyOneClose() {
    var d = DockPresence()
    d.opened("settings")
    d.opened("settings")
    d.closed("settings")
    #expect(!d.showsInDock)
}
