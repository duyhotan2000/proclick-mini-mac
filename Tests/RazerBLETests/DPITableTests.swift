import Testing
@testable import RazerBLE

// Captured 2026-11-06: 36 bytes (header len 0x24) — the final marker byte is NOT sent by this mouse.
let captured = hex("04 05 01 90 01 90 01 00 00 02 20 03 20 03 00 00 03 40 06 40 06 00 00 04 80 0c 80 0c 00 00 05 00 19 00 19 00")

@Test func parsesCapturedTable() throws {
    let t = try DPITable.parse(captured)
    #expect(t.stages.map(\.x) == [400, 800, 1600, 3200, 6400])
    #expect(t.stages.map(\.id) == [1, 2, 3, 4, 5])
    #expect(t.activeID == 4 && t.activeIndex == 3 && t.marker == 0)
}

@Test func roundTripsToWriteLayout() throws {
    let w = try DPITable.parse(captured).encodeForWrite()
    #expect(w.count == 38)
    #expect(Array(w[0..<36]) == captured)  // read bytes + marker(00) + trailing 00
    #expect(w[36] == 0 && w[37] == 0)
}

@Test func parsesFullLengthTableWithMarker() throws {  // OpenSnek devices send 37 bytes
    let t = try DPITable.parse(captured + [0x03])
    #expect(t.stages.count == 5 && t.marker == 3)
    #expect(t.encodeForWrite()[36] == 3)
}

@Test func parsesTruncatedTable() throws {  // reserved byte of the last entry missing too
    let t = try DPITable.parse(Array(captured.dropLast()))
    #expect(t.stages.count == 5 && t.stages[4].y == 6400)
}

@Test func rejectsTableMissingDPIBytes() {
    #expect(throws: DPITableError.self) { try DPITable.parse(Array(captured.dropLast(2))) }
}

@Test func activeResolutionFallbacks() throws {
    var t = try DPITable.parse(captured)
    t.activeID = 9
    #expect(t.activeIndex == 4)  // clamp
    t.stages = Array(t.stages.prefix(3))
    t.activeID = 2
    #expect(t.activeIndex == 1)  // id match
    t.stages = t.stages.map { DPIStage(id: $0.id + 10, x: $0.x, y: $0.y) }
    #expect(t.activeIndex == 1)  // 1-based fallback
}

@Test func fewerStagesPadToFiveEntries() throws {
    var t = try DPITable.parse(captured)
    t.tailSlots = Array(t.stages.suffix(2))
    t.stages = Array(t.stages.prefix(3))
    let w = t.encodeForWrite()
    #expect(w.count == 38 && w[1] == 3)
    #expect(Array(w[2 + 3 * 7..<2 + 4 * 7]) == hex("04 80 0c 80 0c 00 00"))  // tail slot kept
}
