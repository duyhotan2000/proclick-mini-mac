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
