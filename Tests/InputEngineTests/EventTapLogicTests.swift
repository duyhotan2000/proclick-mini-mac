import CoreGraphics
import Foundation
import Testing
@testable import InputEngine

final class TestClock: @unchecked Sendable {
    var now: TimeInterval = 0
}

@Test func reenablesOnDisableEvent() {
    let tap = EventTap { _, event in event }
    var enabled: [Bool] = []
    tap.setEnabled = { enabled.append($0) }
    #expect(tap.handleTapDisabled(type: .tapDisabledByTimeout))
    #expect(tap.handleTapDisabled(type: .tapDisabledByUserInput))
    #expect(enabled == [true, true])
    #expect(!tap.handleTapDisabled(type: .scrollWheel))
    #expect(enabled == [true, true])
}

@Test func tagExpiresAfterWindow() {
    let clock = TestClock()
    let tagger = DeviceTagger(clock: { clock.now })
    tagger.record(HIDValue(usagePage: 0x0C, usage: 0x238, value: 1, timestamp: 0))
    clock.now = 0.01
    #expect(tagger.lastPan(within: 0.05)?.value == 1)
    clock.now = 0.2
    #expect(tagger.lastPan(within: 0.05) == nil)
}

@Test func zeroPanDoesNotTag() {
    let clock = TestClock()
    let tagger = DeviceTagger(clock: { clock.now })
    tagger.record(HIDValue(usagePage: 0x0C, usage: 0x238, value: 0, timestamp: 0))
    #expect(tagger.lastPan(within: 0.05) == nil)
}

@Test func buttonTagRemembersUsage() {
    let clock = TestClock()
    let tagger = DeviceTagger(clock: { clock.now })
    tagger.record(HIDValue(usagePage: 0x09, usage: 4, value: 1, timestamp: 0))
    #expect(tagger.lastButton(within: 0.05)?.usage == 4)
    clock.now = 0.2
    #expect(tagger.lastButton(within: 0.05) == nil)
}
