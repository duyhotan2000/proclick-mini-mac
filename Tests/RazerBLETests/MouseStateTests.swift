import Foundation
import Testing
@testable import RazerBLE

@Test func rejectsOutOfRange() {
    var s = Defaults.factory
    s.dpi.stages[0].x = 12050
    #expect(throws: ValidationError.self) { try validate(s) }
    s = Defaults.factory
    s.dpi.stages[0].y = 425  // not a multiple of 50
    #expect(throws: ValidationError.self) { try validate(s) }
    s = Defaults.factory
    s.sleepSeconds = 30
    #expect(throws: ValidationError.self) { try validate(s) }
    s = Defaults.factory
    s.dpi.stages = []
    #expect(throws: ValidationError.self) { try validate(s) }
}

@Test func acceptsDefaults() throws {
    try validate(Defaults.factory)
    try validate(Defaults.baseline)
}

@Test func factoryAndBaselineValues() {
    #expect(Defaults.factory.dpi.stages[Defaults.factory.dpi.activeIndex].x == 1600)
    #expect(Defaults.baseline.dpi.activeID == 4 && Defaults.baseline.sleepSeconds == 300)
}

@Test func baselineMatchesDocsFile() throws {
    let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("../../docs/device-baseline.json").standardized
    #expect(try JSONDecoder().decode(MouseState.self, from: Data(contentsOf: url)) == Defaults.baseline)
}
