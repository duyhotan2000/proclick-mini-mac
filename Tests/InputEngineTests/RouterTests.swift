import Testing
@testable import InputEngine

@Test func untaggedPanPassesThrough() {
    var d = TiltDebouncer()
    #expect(route(.horizontalScroll(pan: 3, at: 0), tagged: false, table: .default, debouncer: &d) == .pass)
}

@Test func taggedHeldTiltConsumedRunsOnce() {
    var d = TiltDebouncer()
    #expect(route(.horizontalScroll(pan: 1, at: 0), tagged: true, table: .default, debouncer: &d)
        == .consumeAndRun(.nextDesktop))
    #expect(route(.horizontalScroll(pan: 1, at: 0.1), tagged: true, table: .default, debouncer: &d) == .consume)
}

@Test func tiltLeftRunsPreviousDesktop() {
    var d = TiltDebouncer()
    #expect(route(.horizontalScroll(pan: -1, at: 0), tagged: true, table: .default, debouncer: &d)
        == .consumeAndRun(.previousDesktop))
}

@Test func passThroughTiltScrollsNormally() {
    var d = TiltDebouncer()
    var table = MappingTable.default
    table.actions[.tiltRight] = .passThrough
    #expect(route(.horizontalScroll(pan: 1, at: 0), tagged: true, table: table, debouncer: &d) == .pass)
    #expect(route(.horizontalScroll(pan: -1, at: 1), tagged: true, table: table, debouncer: &d)
        == .consumeAndRun(.previousDesktop))
}

@Test func disabledTiltIsSwallowed() {
    var d = TiltDebouncer()
    var table = MappingTable.default
    table.actions[.tiltLeft] = .disabled
    #expect(route(.horizontalScroll(pan: -1, at: 0), tagged: true, table: table, debouncer: &d) == .consume)
}

@Test func sideButtonsPassByDefault() {
    var d = TiltDebouncer()
    #expect(route(.button(.button4, down: true), tagged: true, table: .default, debouncer: &d) == .pass)
    #expect(route(.button(.button5, down: false), tagged: true, table: .default, debouncer: &d) == .pass)
}

@Test func remappedButtonConsumedBothEdges() {
    var d = TiltDebouncer()
    var table = MappingTable.default
    table.actions[.button5] = .missionControl
    #expect(route(.button(.button5, down: true), tagged: true, table: table, debouncer: &d)
        == .consumeAndRun(.missionControl))
    #expect(route(.button(.button5, down: false), tagged: true, table: table, debouncer: &d) == .consume)
}

@Test func remappedButtonFromOtherMousePasses() {
    var d = TiltDebouncer()
    var table = MappingTable.default
    table.actions[.button5] = .missionControl
    #expect(route(.button(.button5, down: true), tagged: false, table: table, debouncer: &d) == .pass)
}

@Test func buttonIDFromHIDNumber() {
    #expect(ButtonID(hidButton: 1) == .left)
    #expect(ButtonID(hidButton: 3) == .wheel)
    #expect(ButtonID(hidButton: 4) == .button4)
    #expect(ButtonID(hidButton: 5) == .button5)
    #expect(ButtonID(hidButton: 6) == nil)
}

@Test func sideButtonsBecomeBackForwardInSafari() {
    var d = TiltDebouncer()
    #expect(route(.button(.button4, down: true), tagged: true, table: .default, debouncer: &d,
                  frontApp: "com.apple.Safari") == .consumeAndRun(.back))
    #expect(route(.button(.button4, down: false), tagged: true, table: .default, debouncer: &d,
                  frontApp: "com.apple.Safari") == .consume)
    #expect(route(.button(.button5, down: true), tagged: true, table: .default, debouncer: &d,
                  frontApp: "com.apple.finder") == .consumeAndRun(.forward))
}

@Test func sideButtonsPassThroughInOtherApps() {
    var d = TiltDebouncer()
    #expect(route(.button(.button4, down: true), tagged: true, table: .default, debouncer: &d,
                  frontApp: "com.google.Chrome") == .pass)
    #expect(route(.button(.button4, down: true), tagged: true, table: .default, debouncer: &d,
                  frontApp: nil) == .pass)
}

private func remapped() -> MappingTable {
    var t = MappingTable.default
    t.actions[.left] = .missionControl
    return t
}

@Test func releasePassesWhenPressPassed() {
    var r = InputRouter(table: remapped())
    #expect(r.route(.button(.left, down: true), tagged: false) == .pass)   // HID value arrived late
    #expect(r.route(.button(.left, down: false), tagged: true) == .pass)   // must not strand the down
}

@Test func releaseConsumedWhenPressConsumed() {
    var r = InputRouter(table: remapped())
    #expect(r.route(.button(.left, down: true), tagged: true) == .consumeAndRun(.missionControl))
    #expect(r.route(.button(.left, down: false), tagged: false) == .consume)  // even if untagged
    #expect(r.route(.button(.left, down: false), tagged: true) == .pass)      // already released
}

@Test func routerStillDebouncesTilts() {
    var r = InputRouter(table: .default)
    #expect(r.route(.horizontalScroll(pan: 1, at: 0), tagged: true) == .consumeAndRun(.nextDesktop))
    #expect(r.route(.horizontalScroll(pan: 1, at: 0.05), tagged: true) == .consume)
}
