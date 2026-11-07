import Foundation

// Framing for the Razer BLE vendor protocol (OpenSnek BLE_PROTOCOL.md §4).
//
// Request:  [req, len, 00, 00, k0, k1, k2, k3] + payload
// Notify:   [req, len, 00, 00, 00, 00, 00, status] then payload frames.

/// A 4-byte vendor key selecting a setting and whether it is read or written.
public struct Key: Hashable, Sendable, CustomStringConvertible {
    public let bytes: [UInt8]

    public init(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8, _ b3: UInt8) {
        bytes = [b0, b1, b2, b3]
    }

    public static let dpiTable = Key(0x0B, 0x84, 0x01, 0x00)
    public static let dpiTableWrite = Key(0x0B, 0x04, 0x01, 0x00)
    public static let activeDPI = Key(0x0B, 0x81, 0x00, 0x00)
    public static let activeStages = Key(0x0B, 0x82, 0x00, 0x00)
    public static let sleep = Key(0x05, 0x84, 0x00, 0x00)
    public static let sleepWrite = Key(0x05, 0x04, 0x00, 0x00)
    public static let batteryRaw = Key(0x05, 0x81, 0x00, 0x01)
    public static let batteryStatus = Key(0x05, 0x80, 0x00, 0x01)

    public var description: String { bytes.map { String(format: "%02X", $0) }.joined(separator: " ") }
}

public enum Status: UInt8, Sendable {
    case ok = 0x02
    case error = 0x03
    case badParam = 0x05
}

public func encodeRequest(req: UInt8, key: Key, payload: [UInt8] = []) -> [UInt8] {
    [req, UInt8(payload.count), 0, 0] + key.bytes + payload
}

/// Maximum bytes per payload write (OpenSnek BLE_PROTOCOL.md §7.2).
public let payloadChunkSize = 20

/// The characteristic writes for one request: the 8-byte header on its own, then the
/// payload in ≤20-byte chunks. Sending header and payload in one write is rejected (status 03).
public func requestWrites(req: UInt8, key: Key, payload: [UInt8] = []) -> [[UInt8]] {
    let header = Array(encodeRequest(req: req, key: key, payload: payload).prefix(8))
    let chunks = stride(from: 0, to: payload.count, by: payloadChunkSize).map {
        Array(payload[$0..<min($0 + payloadChunkSize, payload.count)])
    }
    return [header] + chunks
}

/// Collects notify frames for one exchange and yields its payload.
public struct Reassembler: Sendable {
    public enum Result: Equatable, Sendable {
        case payload([UInt8])
        case failed(Status)
    }

    public let req: UInt8
    private var expected: Int?
    private var buffer: [UInt8] = []

    public init(req: UInt8) {
        self.req = req
    }

    /// Feeds one notify frame. Returns a result once the exchange is complete.
    public mutating func feed(_ frame: [UInt8]) -> Result? {
        guard let expected else {
            guard frame.count >= 8, frame[0] == req, let status = Status(rawValue: frame[7]) else {
                return nil
            }
            if status != .ok { return .failed(status) }
            let length = Int(frame[1])
            if length == 0 { return .payload([]) }
            self.expected = length
            return nil
        }
        buffer += frame
        guard buffer.count >= expected else { return nil }
        return .payload(Array(buffer.prefix(expected)))
    }
}
