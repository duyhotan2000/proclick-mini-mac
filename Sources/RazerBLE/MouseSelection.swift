import Foundation

/// A Pro Click Mini the Mac is connected to.
public struct MouseInfo: Equatable, Hashable, Identifiable, Sendable {
    public let id: UUID
    public let name: String

    public init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
}

/// Which connected device the app talks to. Other Razer Bluetooth mice share the vendor
/// service, so a device must look like a Pro Click Mini by name and then prove it by PnP ID.
enum MouseSelection {
    static let vendorID: UInt16 = 0x1532
    static let productID: UInt16 = 0x009B
    /// How long connecting and discovering may take before we give up and try again.
    static let connectDeadline: TimeInterval = 10

    /// The mouse advertises as "ProClickM"; allow spacing and case variants.
    static func isCandidate(name: String?) -> Bool {
        guard let name else { return false }
        return name.lowercased().replacingOccurrences(of: " ", with: "").contains("proclick")
    }

    /// Device Information › PnP ID (0x2A50): source, vendor (LE), product (LE), version (LE).
    static func parsePnPID(_ bytes: [UInt8]) -> (vendor: UInt16, product: UInt16)? {
        guard bytes.count >= 5 else { return nil }
        return (UInt16(bytes[1]) | UInt16(bytes[2]) << 8, UInt16(bytes[3]) | UInt16(bytes[4]) << 8)
    }

    static func isProClickMini(vendor: UInt16, product: UInt16) -> Bool {
        vendor == vendorID && product == productID
    }

    /// The preferred mouse if it's connected, otherwise the first one that wasn't rejected.
    static func pick(_ mice: [MouseInfo], preferred: UUID?, rejected: Set<UUID>) -> MouseInfo? {
        let usable = mice.filter { !rejected.contains($0.id) }
        return usable.first { $0.id == preferred } ?? usable.first
    }

    static func connectExpired(startedAt: TimeInterval, now: TimeInterval) -> Bool {
        now - startedAt > connectDeadline
    }
}
