import Foundation
import Testing
@testable import RazerBLE

func makeClient(_ mouse: FakeMouse) -> (MouseClient, SnapshotStore) {
    let store = SnapshotStore(directory: tempDir())
    return (MouseClient(transport: mouse, snapshots: store), store)
}

@Test func applyWritesOnlyChangedFields() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, _) = makeClient(mouse)
    var target = Defaults.baseline
    target.sleepSeconds = 600
    #expect(await client.apply(target) == .applied(target))
    #expect(mouse.writes.count == 1)
    #expect(mouse.writes.first?.key == .sleepWrite && mouse.writes.first?.payload == [0x58, 0x02])
}

@Test func dpiWriteSendsFullTableWithCurrentIds() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, _) = makeClient(mouse)
    var target = Defaults.baseline
    target.dpi.stages[3].x = 2400
    target.dpi.stages[3].y = 2400
    target.dpi.stages[3].id = 99  // UI must not be able to invent ids
    guard case .applied = await client.apply(target) else { Issue.record("not applied"); return }
    #expect(mouse.writes.map(\.key) == [.dpiTableWrite])
    #expect(mouse.writes[0].payload.count == 38)
    #expect(mouse.table.stages.map(\.id) == [1, 2, 3, 4, 5])
    #expect(mouse.table.stages[3].x == 2400 && mouse.table.activeID == 4)
}

@Test func snapshotSavedBeforeWrite() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, store) = makeClient(mouse)
    let seen = Locked(false)
    mouse.onWrite = { _ in seen.set((try? store.latest()) == Defaults.baseline) }
    var target = Defaults.baseline
    target.sleepSeconds = 600
    _ = await client.apply(target)
    #expect(seen.get())
}

@Test func mismatchRollsBack() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, _) = makeClient(mouse)
    var target = Defaults.baseline
    target.sleepSeconds = 600
    mouse.stickySleep = 0
    let outcome = await client.apply(target)
    mouse.stickySleep = nil
    guard case .rollbackFailed = outcome else {
        // Sticky value also defeats the restore, so rollback cannot succeed here.
        Issue.record("expected rollbackFailed, got \(outcome)")
        return
    }
}

@Test func mismatchThenRestoreSucceeds() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, _) = makeClient(mouse)
    var target = Defaults.baseline
    target.sleepSeconds = 600
    mouse.stickySleep = 900  // mouse stores the wrong value once…
    mouse.onWrite = { [mouse] _ in if mouse.writes.count == 1 { mouse.stickySleep = nil } }  // …then behaves
    let outcome = await client.apply(target)
    guard case .rolledBack(_, let restored) = outcome else { Issue.record("got \(outcome)"); return }
    #expect(restored == Defaults.baseline && mouse.sleep == 300)
}

@Test func writeTimesOutAndRollsBack() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, _) = makeClient(mouse)
    mouse.failingWrites = 1
    var target = Defaults.baseline
    target.sleepSeconds = 600
    guard case .rolledBack(let reason, let restored) = await client.apply(target) else {
        Issue.record("expected rolledBack"); return
    }
    #expect(reason.contains("timeout"))
    #expect(restored == Defaults.baseline && mouse.sleep == 300)
}

@Test func rollbackFailureReportsSnapshot() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, _) = makeClient(mouse)
    mouse.failingWrites = .max
    var target = Defaults.baseline
    target.sleepSeconds = 600
    guard case .rollbackFailed(_, let snapshot) = await client.apply(target) else {
        Issue.record("expected rollbackFailed"); return
    }
    #expect(FileManager.default.fileExists(atPath: snapshot.path))
}

@Test func invalidTargetNeverWrites() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, _) = makeClient(mouse)
    var target = Defaults.baseline
    target.dpi.stages[0].x = 50
    guard case .notApplied = await client.apply(target) else { Issue.record("expected notApplied"); return }
    #expect(mouse.writes.isEmpty)
}

@Test func unchangedTargetWritesNothing() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, _) = makeClient(mouse)
    #expect(await client.apply(Defaults.baseline) == .applied(Defaults.baseline))
    #expect(mouse.writes.isEmpty)
}

@Test func restoreFactorySetsActive1600() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 600)
    let (client, _) = makeClient(mouse)
    guard case .applied = await client.restoreFactory() else { Issue.record("not applied"); return }
    #expect(mouse.table.stages[mouse.table.activeIndex].x == 1600 && mouse.sleep == 300)
}

@Test func restoreOriginalReturnsToBaseline() async throws {
    var start = try DPITable.parse(captured)
    start.stages[3].x = 2400
    start.stages[3].y = 2400
    let mouse = FakeMouse(dpiBytes: Array(start.encodeForWrite().prefix(36)), sleep: 600)
    let (client, _) = makeClient(mouse)
    guard case .applied = await client.restoreOriginal() else { Issue.record("not applied"); return }
    #expect(MouseState(dpi: mouse.table, sleepSeconds: mouse.sleep) == Defaults.baseline)
}

final class Locked<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: T
    init(_ v: T) { value = v }
    func get() -> T { lock.withLock { value } }
    func set(_ v: T) { lock.withLock { value = v } }
}

@Test func rollbackOnlyRewritesAttemptedFields() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, _) = makeClient(mouse)
    mouse.failingWrites = 1
    var target = Defaults.baseline
    target.sleepSeconds = 600
    _ = await client.apply(target)
    #expect(mouse.writes.map(\.key) == [.sleepWrite, .sleepWrite])
}

@Test func forceWritesUnchangedFields() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, _) = makeClient(mouse)
    guard case .applied = await client.apply(Defaults.baseline, force: [.dpi, .sleep]) else { Issue.record("not applied"); return }
    #expect(mouse.writes.map(\.key) == [.dpiTableWrite, .sleepWrite])
    #expect(mouse.writes[0].payload == captured + [0, 0])  // identical table, byte for byte
}

@Test func forceOnlyNamedFields() async {
    let mouse = FakeMouse(dpiBytes: captured, sleep: 300)
    let (client, _) = makeClient(mouse)
    guard case .applied = await client.apply(Defaults.baseline, force: [.sleep]) else { Issue.record("not applied"); return }
    #expect(mouse.writes.map(\.key) == [.sleepWrite])
}
