import Foundation
import Testing
@testable import InputEngine

private func config(ignore: String?) throws -> URL {
    let ignoreLine = ignore.map { ",\n \"ignore\": \($0)" } ?? ""
    let json = """
        {"global": {"show_in_menu_bar": false},
         "profiles": [{"name": "Default profile", "selected": true,
           "devices": [{"identifiers": {"is_keyboard": true, "is_pointing_device": true,
                                         "product_id": 155, "vendor_id": 5426}\(ignoreLine)}]}]}
        """
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("karabiner-\(UUID()).json")
    try Data(json.utf8).write(to: url)
    return url
}

@Test func ignoredMouseIsNotGrabbed() throws {
    #expect(!KarabinerCheck.grabsProClick(configURL: try config(ignore: "true")))
}

@Test func notIgnoredMouseIsGrabbed() throws {
    #expect(KarabinerCheck.grabsProClick(configURL: try config(ignore: "false")))
}

@Test func entryWithoutIgnoreIsGrabbed() throws {
    #expect(KarabinerCheck.grabsProClick(configURL: try config(ignore: nil)))
}

@Test func missingConfigIsNotGrabbed() {
    let url = URL(fileURLWithPath: "/nonexistent/karabiner.json")
    #expect(!KarabinerCheck.grabsProClick(configURL: url))
}
