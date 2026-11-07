/// Attributes write-with-response callbacks to the exchange that issued them. CoreBluetooth
/// answers writes in order, so after an exchange ends early its remaining callbacks are the
/// next ones to arrive, and must not fail the exchange that follows (often the rollback).
struct WriteTracker {
    private var current = 0
    private var stale = 0

    mutating func issue(_ count: Int) {
        current += count
    }

    /// The current exchange is over; its unanswered writes become stale.
    mutating func finishExchange() {
        stale += current
        current = 0
    }

    /// Call per write callback. True when it belongs to the current exchange.
    mutating func complete() -> Bool {
        if stale > 0 {
            stale -= 1
            return false
        }
        current = max(current - 1, 0)
        return true
    }

    /// The link dropped: no more callbacks will arrive for earlier writes.
    mutating func reset() {
        current = 0
        stale = 0
    }
}
