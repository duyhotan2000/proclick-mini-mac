import Testing
@testable import RazerBLE

@Test func readStateParsesFakeBytes() async throws {
    let fake = FakeTransport()
    fake.reply(.dpiTable, captured)
    fake.reply(.sleep, [0x2C, 0x01])
    let client = MouseClient(transport: fake)
    #expect(try await client.readState() == Defaults.baseline)
}

@Test func readsActiveDPIAndBattery() async throws {
    let fake = FakeTransport()
    fake.reply(.activeDPI, hex("80 0c 80 0c 00 00"))
    fake.reply(.batteryRaw, [0x38])
    let client = MouseClient(transport: fake)
    let dpi = try await client.readActiveDPI()
    #expect(dpi.x == 3200 && dpi.y == 3200)
    #expect(try await client.readBatteryRaw() == 56)
}

@Test func transportFailsPendingOnDisconnect() async {
    let fake = FakeTransport()
    fake.fail(.dpiTable, .notConnected)
    let client = MouseClient(transport: fake)
    await #expect(throws: TransportError.notConnected) { try await client.readState() }
}

@Test func shortSleepPayloadThrows() async {
    let fake = FakeTransport()
    fake.reply(.dpiTable, captured)
    fake.reply(.sleep, [0x2C])
    let client = MouseClient(transport: fake)
    await #expect(throws: MouseClientError.self) { try await client.readState() }
}
