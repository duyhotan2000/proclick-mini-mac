import Foundation
import Testing
@testable import RazerBLE

func tempDir() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("proclick-tests-\(UUID().uuidString)")
}

@Test func snapshotRoundTrip() throws {
    let store = SnapshotStore(directory: tempDir())
    let url = try store.save(Defaults.baseline, reason: "test")
    #expect(FileManager.default.fileExists(atPath: url.path))
    #expect(url.lastPathComponent.hasSuffix("-test.json"))
    #expect(try store.latest() == Defaults.baseline)
}

@Test func latestPicksNewest() throws {
    let store = SnapshotStore(directory: tempDir())
    _ = try store.save(Defaults.baseline, reason: "a")
    _ = try store.save(Defaults.factory, reason: "b")
    #expect(try store.latest() == Defaults.factory)
}

@Test func latestIsNilWhenEmpty() throws {
    #expect(try SnapshotStore(directory: tempDir()).latest() == nil)
}
