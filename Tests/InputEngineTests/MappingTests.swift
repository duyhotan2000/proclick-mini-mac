import Foundation
import Testing
@testable import InputEngine

@Test func defaultMapping() {
    let t = MappingTable.default
    #expect(t.action(for: .tiltLeft) == .previousDesktop)
    #expect(t.action(for: .tiltRight) == .nextDesktop)
    for b in ButtonID.allCases where b != .tiltLeft && b != .tiltRight {
        #expect(t.action(for: b) == .passThrough)
    }
}

@Test func mappingCodableRoundTrip() throws {
    var t = MappingTable.default
    t.actions[.button4] = .shortcut(keyCode: 0x7B, modifiers: 0x40000)
    t.actions[.wheel] = .media(.playPause)
    let data = try JSONEncoder().encode(t)
    #expect(try JSONDecoder().decode(MappingTable.self, from: data) == t)
    #expect(String(decoding: data, as: UTF8.self).contains("\"button4\""))  // readable keys
}
