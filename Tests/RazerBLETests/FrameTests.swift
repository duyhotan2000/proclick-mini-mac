import Testing
@testable import RazerBLE

@Test func encodesReadRequest() {
    #expect(encodeRequest(req: 0x31, key: .dpiTable) == [0x31, 0, 0, 0, 0x0B, 0x84, 0x01, 0x00])
}

@Test func encodesWriteRequestWithLength() {
    #expect(encodeRequest(req: 0x40, key: .sleepWrite, payload: [0x2C, 0x01])
        == [0x40, 0x02, 0, 0, 0x05, 0x04, 0, 0, 0x2C, 0x01])
}

@Test func reassemblesDPITableFromCapture() {
    var r = Reassembler(req: 0x31)
    // Stale frame from an earlier exchange must be ignored.
    #expect(r.feed(hex("01 00 00 00 00 00 00 03 50 76 0f 8d 6e 04 98 fa 4b 2d 72 ed")) == nil)
    #expect(r.feed(hex("31 24 00 00 00 00 00 02 50 76 0f 8d 6e 04 98 fa 4b 2d 72 ed")) == nil)
    #expect(r.feed(hex("04 05 01 90 01 90 01 00 00 02 20 03 20 03 00 00 03 40 06 40")) == nil)
    // Header len 0x24 = 36 bytes; the trailing "03 40 06 40" is stale buffer.
    #expect(r.feed(hex("06 00 00 04 80 0c 80 0c 00 00 05 00 19 00 19 00 03 40 06 40"))
        == .payload(hex("04 05 01 90 01 90 01 00 00 02 20 03 20 03 00 00 03 40 06 40 06 00 00 04 80 0c 80 0c 00 00 05 00 19 00 19 00")))
}

@Test func reassemblesSleep() {
    var r = Reassembler(req: 0x32)
    _ = r.feed(hex("32 02 00 00 00 00 00 02 00 00 05 00 19 00 19 00 03 40 06 40"))
    #expect(r.feed(hex("2c 01 00 00 00 00 00 02 00 00 05 00 19 00 19 00 03 40 06 40")) == .payload([0x2C, 0x01]))
}

@Test func failsOnErrorStatus() {
    var r = Reassembler(req: 0x33)
    #expect(r.feed(hex("33 00 00 00 00 00 00 05")) == .failed(.badParam))
}

@Test func zeroLengthCompletesOnHeader() {
    var r = Reassembler(req: 0x34)
    #expect(r.feed(hex("34 00 00 00 00 00 00 02")) == .payload([]))
}
