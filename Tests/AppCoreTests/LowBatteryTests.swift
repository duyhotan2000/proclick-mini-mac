import Testing
@testable import AppCore

@Test func notifiesOnceBelowThreshold() {
    var n = LowBatteryNotifier()
    #expect([22, 16, 15, 14, 10].map { n.update(percent: $0) } == [false, false, true, false, false])
}

@Test func rearmsAfterRecovery() {
    var n = LowBatteryNotifier()
    #expect([15, 25, 15].map { n.update(percent: $0) } == [true, false, true])
}

@Test func staysQuietBetweenThresholds() {
    var n = LowBatteryNotifier()
    #expect([15, 18, 14].map { n.update(percent: $0) } == [true, false, false])
}
