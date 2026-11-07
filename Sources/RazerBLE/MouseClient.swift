import Foundation

public enum MouseClientError: Error, Equatable {
    case shortPayload(Key, Int)
}

public enum WriteOutcome: Equatable, Sendable {
    /// The mouse now holds these settings (read back after writing).
    case applied(MouseState)
    /// Nothing was written (invalid target, or the current settings couldn't be read).
    case notApplied(reason: String)
    /// The write failed or didn't stick; the previous settings were restored and verified.
    case rolledBack(reason: String, restored: MouseState)
    /// Restoring failed too. `snapshot` holds the settings from before the write.
    case rollbackFailed(reason: String, snapshot: URL)
}

/// Typed access to the mouse's settings over a `VendorTransport`.
public actor MouseClient {
    let transport: VendorTransport
    let snapshots: SnapshotStore

    public init(transport: VendorTransport, snapshots: SnapshotStore = .default) {
        self.transport = transport
        self.snapshots = snapshots
    }

    public func readState() async throws -> MouseState {
        let dpi = try DPITable.parse(try await transport.exchange(key: .dpiTable, payload: []))
        let sleep = try await transport.exchange(key: .sleep, payload: [])
        return MouseState(dpi: dpi, sleepSeconds: try Self.u16(sleep, key: .sleep))
    }

    /// Raw battery level, 0–255.
    public func readBatteryRaw() async throws -> UInt8 {
        let p = try await transport.exchange(key: .batteryRaw, payload: [])
        guard let v = p.first else { throw MouseClientError.shortPayload(.batteryRaw, p.count) }
        return v
    }

    public func readActiveDPI() async throws -> (x: UInt16, y: UInt16) {
        let p = try await transport.exchange(key: .activeDPI, payload: [])
        guard p.count >= 4 else { throw MouseClientError.shortPayload(.activeDPI, p.count) }
        return (try Self.u16(Array(p[0..<2]), key: .activeDPI), try Self.u16(Array(p[2..<4]), key: .activeDPI))
    }

    static func u16(_ p: [UInt8], key: Key) throws -> UInt16 {
        guard p.count >= 2 else { throw MouseClientError.shortPayload(key, p.count) }
        return UInt16(p[0]) | UInt16(p[1]) << 8
    }

    // MARK: Writing

    public func restoreOriginal() async -> WriteOutcome { await apply(Defaults.baseline) }
    public func restoreFactory() async -> WriteOutcome { await apply(Defaults.factory) }

    /// Snapshot → write changed fields → read back → on any mismatch or error, restore the snapshot.
    /// `force` names fields to write even when unchanged (used to validate writes with known-good values).
    public func apply(_ target: MouseState, force: Set<Field> = []) async -> WriteOutcome {
        do {
            try validate(target)
        } catch let e as ValidationError {
            return .notApplied(reason: e.message)
        } catch {
            return .notApplied(reason: "\(error)")
        }

        let current: MouseState
        let snapshot: URL
        do {
            current = try await readState()
        } catch {
            return .notApplied(reason: "Couldn't read the mouse's current settings: \(error)")
        }
        do {
            snapshot = try snapshots.save(current, reason: "before-write")
        } catch {
            return .notApplied(reason: "Couldn't save a backup before writing: \(error)")
        }

        let wanted = Self.merge(target, onto: current)
        let failure: String
        do {
            try await write(wanted, fields: Self.changedFields(current, wanted).union(force))
            let after = try await readState()
            if Self.sameSettings(after, wanted) { return .applied(after) }
            failure = "The mouse didn't keep the new settings."
        } catch {
            failure = "Write failed: \(error)"
        }

        do {
            // Rewrite every field we attempted, whether or not its write appeared to succeed.
            try await write(current, fields: Self.changedFields(current, wanted).union(force))
            let restored = try await readState()
            if Self.sameSettings(restored, current) {
                return .rolledBack(reason: failure, restored: restored)
            }
            return .rollbackFailed(reason: failure + " Restoring didn't stick either.", snapshot: snapshot)
        } catch {
            return .rollbackFailed(reason: failure + " Restoring failed: \(error)", snapshot: snapshot)
        }
    }

    public enum Field: Hashable, Sendable {
        case dpi
        case sleep
    }

    public static func changedFields(_ a: MouseState, _ b: MouseState) -> Set<Field> {
        var fields: Set<Field> = []
        if !sameDPI(a.dpi, b.dpi) { fields.insert(.dpi) }
        if a.sleepSeconds != b.sleepSeconds { fields.insert(.sleep) }
        return fields
    }

    private func write(_ s: MouseState, fields: Set<Field>) async throws {
        if fields.contains(.dpi) {
            _ = try await transport.exchange(key: .dpiTableWrite, payload: s.dpi.encodeForWrite())
        }
        if fields.contains(.sleep) {
            _ = try await transport.exchange(key: .sleepWrite,
                                             payload: [UInt8(s.sleepSeconds & 0xFF), UInt8(s.sleepSeconds >> 8)])
        }
    }

    /// The target's values with the stage ids, marker and spare slots the mouse currently uses.
    public static func merge(_ target: MouseState, onto current: MouseState) -> MouseState {
        let slots = current.dpi.stages + current.dpi.tailSlots
        var stages: [DPIStage] = []
        for (i, s) in target.dpi.stages.enumerated() {
            let id = i < slots.count ? slots[i].id : (stages.last?.id ?? 0) &+ 1
            stages.append(DPIStage(id: id, x: s.x, y: s.y))
        }
        let active = stages[min(target.dpi.activeIndex, stages.count - 1)].id
        let tail = Array(slots.dropFirst(stages.count))
        return MouseState(dpi: DPITable(activeID: active, stages: stages, marker: current.dpi.marker, tailSlots: tail),
                          sleepSeconds: target.sleepSeconds)
    }

    public static func sameDPI(_ a: DPITable, _ b: DPITable) -> Bool {
        a.stages.map { [$0.x, $0.y] } == b.stages.map { [$0.x, $0.y] } && a.activeIndex == b.activeIndex
    }

    public static func sameSettings(_ a: MouseState, _ b: MouseState) -> Bool {
        sameDPI(a.dpi, b.dpi) && a.sleepSeconds == b.sleepSeconds
    }
}
