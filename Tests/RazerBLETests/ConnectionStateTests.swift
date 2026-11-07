import Testing
@testable import RazerBLE

@Test func notFoundBeforeFirstConnectionIsSearching() {
    #expect(CoreBluetoothTransport.stateWhenNotFound(current: .searching) == .searching)
}

@Test func notFoundAfterDropStaysDisconnected() {
    #expect(CoreBluetoothTransport.stateWhenNotFound(current: .disconnected) == .disconnected)
}
