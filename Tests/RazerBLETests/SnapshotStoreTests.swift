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

@Test func originalIsSavedOnlyOncePerMouse() throws {
    let store = SnapshotStore(directory: tempDir())
    let mouse = UUID()
    #expect(try store.saveOriginalIfMissing(Defaults.baseline, mouse: mouse))
    #expect(try !store.saveOriginalIfMissing(Defaults.factory, mouse: mouse))
    #expect(store.original(for: mouse) == Defaults.baseline)
    #expect(store.original(for: UUID()) == nil)
    #expect(try store.list().isEmpty)  // originals aren't before-write snapshots
}
