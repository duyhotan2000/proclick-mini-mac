import Testing
@testable import InputEngine

// From docs/hid-capture.md: left = -1, right = +1, repeats every ~22 ms while held.

@Test func oneTiltOneEvent() {
    var d = TiltDebouncer()
    #expect(d.handle(pan: -1, at: 0.00) == .left)
    for t in stride(from: 0.022, through: 2.0, by: 0.022) { #expect(d.handle(pan: -1, at: t) == nil) }  // held 2 s
    #expect(d.handle(pan: -1, at: 2.40) == .left)  // new tilt after silence
}

@Test func rightIsPositive() {
    var d = TiltDebouncer()
    #expect(d.handle(pan: 1, at: 0) == .right)
}

@Test func reversalFiresImmediately() {
    var d = TiltDebouncer()
    _ = d.handle(pan: 1, at: 0)
    #expect(d.handle(pan: -1, at: 0.05) == .left)
}

@Test func zeroPanIsIgnored() {
    var d = TiltDebouncer()
    _ = d.handle(pan: 1, at: 0)
    #expect(d.handle(pan: 0, at: 0.1) == nil)
    #expect(d.handle(pan: 1, at: 0.2) == nil)  // zeros don't end the gesture
}

@Test func gapShorterThanWindowStaysOneGesture() {
    var d = TiltDebouncer()
    _ = d.handle(pan: 1, at: 0)
    #expect(d.handle(pan: 1, at: 0.24) == nil)
    #expect(d.handle(pan: 1, at: 0.48) == nil)  // window extends from the last pan
    #expect(d.handle(pan: 1, at: 0.74) == .right)
}
