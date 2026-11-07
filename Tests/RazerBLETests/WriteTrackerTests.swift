import Testing
@testable import RazerBLE

@Test func lateCallbacksFromAbandonedExchangeAreIgnored() {
    var t = WriteTracker()
    var owned: [Bool] = []
    t.issue(3)                     // exchange A: header + 2 chunks
    owned.append(t.complete())     // A's header write → belongs to A
    t.finishExchange()             // A failed; its 2 chunk callbacks are still in flight
    t.issue(1)                     // rollback exchange B
    owned.append(t.complete())     // A's chunk 1 → ignore
    owned.append(t.complete())     // A's chunk 2 → ignore
    owned.append(t.complete())     // B's write → belongs to B
    #expect(owned == [true, false, false, true])
}

@Test func resetForgetsInFlightWrites() {
    var t = WriteTracker()
    t.issue(2)
    t.finishExchange()
    t.reset()                      // disconnected: those callbacks will never come
    t.issue(1)
    let owned = t.complete()
    #expect(owned)
}
