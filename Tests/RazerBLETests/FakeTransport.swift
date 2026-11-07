import Foundation
@testable import RazerBLE

/// In-memory stand-in for the mouse: canned replies per key, or an error.
final class FakeTransport: VendorTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var replies: [Key: Result<[UInt8], TransportError>] = [:]
    private(set) var log: [(key: Key, payload: [UInt8])] = []

    func reply(_ key: Key, _ bytes: [UInt8]) { lock.withLock { replies[key] = .success(bytes) } }
    func fail(_ key: Key, _ error: TransportError) { lock.withLock { replies[key] = .failure(error) } }

    func exchange(key: Key, payload: [UInt8]) async throws -> [UInt8] {
        let r: Result<[UInt8], TransportError>? = lock.withLock {
            log.append((key, payload))
            return replies[key]
        }
        guard let r else { throw TransportError.status(.badParam) }
        return try r.get()
    }

    var connectionState: AsyncStream<ConnectionState> {
        AsyncStream { $0.yield(.connected(name: "Fake")) }
    }
}

/// Stateful stand-in for the mouse: writes change what later reads return.
final class FakeMouse: VendorTransport, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var dpiBytes: [UInt8]
    private(set) var sleep: UInt16
    private(set) var writes: [(key: Key, payload: [UInt8])] = []
    /// When set, the mouse stores this sleep value whatever is written.
    var stickySleep: UInt16?
    /// Number of upcoming writes that fail with `.timeout`; `Int.max` fails all.
    var failingWrites = 0
    /// Called just before a write is applied.
    var onWrite: (@Sendable (Key) -> Void)?

    init(dpiBytes: [UInt8], sleep: UInt16) {
        self.dpiBytes = dpiBytes
        self.sleep = sleep
    }

    var table: DPITable { try! DPITable.parse(lock.withLock { dpiBytes }) }

    func exchange(key: Key, payload: [UInt8]) async throws -> [UInt8] {
        if key == .dpiTableWrite || key == .sleepWrite {
            onWrite?(key)
            return try lock.withLock {
                writes.append((key, payload))
                if failingWrites > 0 {
                    if failingWrites != .max { failingWrites -= 1 }
                    throw TransportError.timeout
                }
                if key == .sleepWrite {
                    sleep = stickySleep ?? (UInt16(payload[0]) | UInt16(payload[1]) << 8)
                } else {
                    dpiBytes = Array(payload.prefix(36))  // mouse reads back 36 bytes
                }
                return []
            }
        }
        return try lock.withLock {
            switch key {
            case .dpiTable: return dpiBytes
            case .sleep: return [UInt8(sleep & 0xFF), UInt8(sleep >> 8)]
            default: throw TransportError.status(.badParam)
            }
        }
    }

    var connectionState: AsyncStream<ConnectionState> {
        AsyncStream { $0.yield(.connected(name: "FakeMouse")) }
    }
}
