import Foundation

public enum MouseClientError: Error, Equatable {
    case shortPayload(Key, Int)
}

/// Typed access to the mouse's settings over a `VendorTransport`.
public actor MouseClient {
    let transport: VendorTransport

    public init(transport: VendorTransport) {
        self.transport = transport
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
}
