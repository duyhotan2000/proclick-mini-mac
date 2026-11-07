import Foundation

// DPI stage table (OpenSnek BLE_PROTOCOL.md §6.2).
//
// Read:  [active][count] + count..5 entries of [id, x_lo, x_hi, y_lo, y_hi, 00, marker]
//        This mouse sends 36 bytes: the last entry's marker byte is omitted.
// Write: always 5 entries + trailing 00 = 38 bytes.

public struct DPIStage: Codable, Equatable, Sendable {
    public var id: UInt8
    public var x: UInt16
    public var y: UInt16

    public init(id: UInt8, x: UInt16, y: UInt16) {
        self.id = id
        self.x = x
        self.y = y
    }
}

public enum DPITableError: Error, Equatable {
    case tooShort(Int)
    case badCount(UInt8)
}

public struct DPITable: Codable, Equatable, Sendable {
    /// Stage-id token of the active stage, as the mouse reports it.
    public var activeID: UInt8
    /// The first `count` entries, in wire order.
    public var stages: [DPIStage]
    /// Final byte of the fifth entry, preserved from the last read (0 when absent).
    public var marker: UInt8
    /// Entries after `count`, preserved so writes don't disturb unused slots.
    public var tailSlots: [DPIStage]

    public init(activeID: UInt8, stages: [DPIStage], marker: UInt8 = 0, tailSlots: [DPIStage] = []) {
        self.activeID = activeID
        self.stages = stages
        self.marker = marker
        self.tailSlots = tailSlots
    }

    static let entrySize = 7
    static let slotCount = 5

    public static func parse(_ p: [UInt8]) throws -> DPITable {
        guard p.count >= 2 else { throw DPITableError.tooShort(p.count) }
        let count = Int(p[1])
        guard (1...slotCount).contains(count) else { throw DPITableError.badCount(p[1]) }

        func entry(_ i: Int) -> DPIStage? {
            let o = 2 + i * entrySize
            guard p.count >= o + 5 else { return nil }
            return DPIStage(id: p[o], x: UInt16(p[o + 1]) | UInt16(p[o + 2]) << 8,
                            y: UInt16(p[o + 3]) | UInt16(p[o + 4]) << 8)
        }

        var stages: [DPIStage] = []
        for i in 0..<count {
            guard let s = entry(i) else { throw DPITableError.tooShort(p.count) }
            stages.append(s)
        }
        let tail = (count..<slotCount).compactMap(entry)
        let markerOffset = 2 + (slotCount - 1) * entrySize + 6
        let marker = p.count > markerOffset ? p[markerOffset] : 0
        return DPITable(activeID: p[0], stages: stages, marker: marker, tailSlots: tail)
    }

    public func encodeForWrite() -> [UInt8] {
        var slots = Array((stages + tailSlots).prefix(Self.slotCount))
        while slots.count < Self.slotCount, let last = slots.last {
            slots.append(DPIStage(id: last.id &+ 1, x: last.x, y: last.y))
        }
        var out: [UInt8] = [activeID, UInt8(stages.count)]
        for (i, s) in slots.enumerated() {
            out += [s.id, UInt8(s.x & 0xFF), UInt8(s.x >> 8), UInt8(s.y & 0xFF), UInt8(s.y >> 8), 0,
                    i == Self.slotCount - 1 ? marker : 0]
        }
        return out + [0]
    }

    /// Index into `stages` of the active stage: by id, then 1-based index, then clamped.
    public var activeIndex: Int {
        if let i = stages.firstIndex(where: { $0.id == activeID }) { return i }
        let n = Int(activeID)
        if (1...max(stages.count, 1)).contains(n) { return n - 1 }
        return min(max(n, 0), max(stages.count - 1, 0))
    }
}
