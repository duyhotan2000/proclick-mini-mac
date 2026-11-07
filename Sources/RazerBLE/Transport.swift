@preconcurrency import CoreBluetooth
import Foundation

public enum ConnectionState: Equatable, Sendable {
    case searching
    case connected(name: String)
    case disconnected
}

public enum TransportError: Error, Equatable {
    case notConnected
    case timeout
    case status(Status)
    case bluetoothUnavailable(String)
    /// The ATT write itself failed (as opposed to the mouse answering with an error status).
    case writeRejected(String)
}

/// One request/response exchange with the mouse's Razer vendor GATT service.
public protocol VendorTransport: AnyObject, Sendable {
    func exchange(key: Key, payload: [UInt8]) async throws -> [UInt8]
    var connectionState: AsyncStream<ConnectionState> { get }
}

public enum VendorUUID {
    public static let service = CBUUID(string: "52401523-F97C-7F90-0E7F-6C6F4E36DB1C")
    public static let write = CBUUID(string: "52401524-F97C-7F90-0E7F-6C6F4E36DB1C")
    public static let notify = CBUUID(string: "52401525-F97C-7F90-0E7F-6C6F4E36DB1C")
    static let batteryService = CBUUID(string: "180F")
    static let batteryLevel = CBUUID(string: "2A19")
    static let deviceInfoService = CBUUID(string: "180A")
    static let pnpID = CBUUID(string: "2A50")
}

/// Runs async operations one at a time, in call order.
actor SerialGate {
    private var tail: Task<Void, Never>?

    func run<T: Sendable>(_ op: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task {
            await previous?.value
            return try await op()
        }
        tail = Task { _ = try? await task.value }
        return try await task.value
    }
}

/// Talks to the already-paired Pro Click Mini through CoreBluetooth.
///
/// All CoreBluetooth state is confined to `queue`. macOS keeps owning the mouse's
/// HID connection; we attach to the same peripheral via `retrieveConnectedPeripherals`.
public final class CoreBluetoothTransport: NSObject, VendorTransport, @unchecked Sendable {
    public static let exchangeTimeout: TimeInterval = 2
    static let retryInterval: TimeInterval = 3

    private let queue = DispatchQueue(label: "proclick.ble")
    private let gate = SerialGate()
    private var central: CBCentralManager!
    private var peripheral: CBPeripheral?
    private var writeCharacteristic: CBCharacteristic?
    private var nextReq: UInt8 = 0x30
    private var pending: Pending?
    private var state: ConnectionState = .searching
    private var stateObservers: [UUID: AsyncStream<ConnectionState>.Continuation] = [:]
    private var batteryObservers: [UUID: AsyncStream<Int>.Continuation] = [:]
    private var lastBattery: Int?
    private var retryScheduled = false
    private var writes = WriteTracker()
    private var preferred: UUID?
    private var mice: [MouseInfo] = []
    private var miceObservers: [UUID: AsyncStream<[MouseInfo]>.Continuation] = [:]
    /// Devices whose PnP ID showed they aren't a Pro Click Mini.
    private var rejected: Set<UUID> = []
    private var connectStartedAt: TimeInterval?
    private var verifiedPnP: (vendor: UInt16, product: UInt16)?

    private struct Pending {
        var reassembler: Reassembler
        let continuation: CheckedContinuation<[UInt8], Error>
        let timeout: DispatchWorkItem
    }

    /// `preferred` is the mouse to use when several Pro Click Minis are connected.
    public init(preferred: UUID? = nil) {
        self.preferred = preferred
        super.init()
        central = CBCentralManager(delegate: self, queue: queue)
    }

    // MARK: Public API

    public func exchange(key: Key, payload: [UInt8]) async throws -> [UInt8] {
        try await gate.run { [self] in try await performExchange(key: key, payload: payload) }
    }

    public var connectionState: AsyncStream<ConnectionState> {
        AsyncStream { continuation in
            let id = UUID()
            queue.async { [self] in
                stateObservers[id] = continuation
                continuation.yield(state)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                queue.async { self.stateObservers[id] = nil }
            }
        }
    }

    /// Battery percentage from the standard GATT Battery Level characteristic.
    /// Whether the Mac's Bluetooth radio is on.
    public var isPoweredOn: Bool {
        queue.sync { central.state == .poweredOn }
    }

    public var batteryPercent: AsyncStream<Int> {
        AsyncStream { continuation in
            let id = UUID()
            queue.async { [self] in
                batteryObservers[id] = continuation
                if let lastBattery { continuation.yield(lastBattery) }
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                queue.async { self.batteryObservers[id] = nil }
            }
        }
    }

    /// The Pro Click Minis the Mac is connected to.
    public var connectedMice: AsyncStream<[MouseInfo]> {
        AsyncStream { continuation in
            let id = UUID()
            queue.async { [self] in
                miceObservers[id] = continuation
                continuation.yield(mice)
            }
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                queue.async { self.miceObservers[id] = nil }
            }
        }
    }

    /// The mouse settings are read from and written to, once connected.
    public var currentMouseID: UUID? {
        queue.sync {
            guard case .connected = state else { return nil }
            return peripheral?.identifier
        }
    }

    /// Vendor and product from the connected device's PnP ID, if it has been read.
    public var pnpID: (vendor: UInt16, product: UInt16)? {
        queue.sync { verifiedPnP }
    }

    /// Talk to this mouse from now on (it must be one of `connectedMice`).
    public func select(_ id: UUID) {
        queue.async { [self] in
            preferred = id
            guard let current = peripheral, current.identifier != id, mice.contains(where: { $0.id == id }) else {
                return
            }
            abandon(current)
            findPeripheral()
        }
    }

    /// Waits until the vendor channel is ready, or throws `.notConnected` after `timeout`.
    public func waitUntilConnected(timeout: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if case .connected = queue.sync(execute: { state }) { return }
            try await Task.sleep(for: .milliseconds(200))
        }
        throw TransportError.notConnected
    }

    // MARK: Exchange

    private func performExchange(key: Key, payload: [UInt8]) async throws -> [UInt8] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async { [self] in
                guard let peripheral, let writeCharacteristic, case .connected = state else {
                    continuation.resume(throwing: TransportError.notConnected)
                    return
                }
                let req = nextReq
                nextReq = nextReq == 0xFF ? 0x30 : nextReq + 1
                let timeout = DispatchWorkItem { [self] in finishPending(.failure(TransportError.timeout)) }
                pending = Pending(reassembler: Reassembler(req: req), continuation: continuation, timeout: timeout)
                queue.asyncAfter(deadline: .now() + Self.exchangeTimeout, execute: timeout)
                // CoreBluetooth sends queued write-with-response requests in order.
                let chunks = requestWrites(req: req, key: key, payload: payload)
                writes.issue(chunks.count)
                for chunk in chunks {
                    peripheral.writeValue(Data(chunk), for: writeCharacteristic, type: .withResponse)
                }
            }
        }
    }

    private func finishPending(_ result: Result<[UInt8], Error>) {
        guard let p = pending else { return }
        pending = nil
        writes.finishExchange()
        p.timeout.cancel()
        p.continuation.resume(with: result)
    }

    // MARK: Connection

    private func setState(_ new: ConnectionState) {
        guard new != state else { return }
        state = new
        for o in stateObservers.values { o.yield(new) }
    }

    /// Runs every `retryInterval`: refreshes the list of connected Pro Click Minis, connects to
    /// the chosen one, and gives up on a connection attempt that has stalled.
    private func findPeripheral() {
        retryScheduled = false
        defer { scheduleRetry() }
        guard central.state == .poweredOn else { return }
        let found = central.retrieveConnectedPeripherals(withServices: [VendorUUID.service])
            .filter { MouseSelection.isCandidate(name: $0.name) && !rejected.contains($0.identifier) }
        let list = found.map { MouseInfo(id: $0.identifier, name: $0.name ?? "Pro Click Mini") }
        if list != mice {
            mice = list
            for o in miceObservers.values { o.yield(list) }
        }
        if let current = peripheral {
            if case .connected = state { return }
            if let started = connectStartedAt,
               MouseSelection.connectExpired(startedAt: started, now: ProcessInfo.processInfo.systemUptime) {
                abandon(current)
            }
            return
        }
        guard let choice = MouseSelection.pick(list, preferred: preferred, rejected: rejected),
              let p = found.first(where: { $0.identifier == choice.id }) else {
            setState(Self.stateWhenNotFound(current: state))
            return
        }
        peripheral = p
        p.delegate = self
        connectStartedAt = ProcessInfo.processInfo.systemUptime
        central.connect(p)
    }

    /// Stops using `p` (it stays connected to macOS for normal mouse input).
    private func abandon(_ p: CBPeripheral) {
        p.delegate = nil
        central.cancelPeripheralConnection(p)
        dropPeripheral()
    }

    /// "Searching" until the mouse is first found; after it drops, stay "disconnected" while retrying.
    static func stateWhenNotFound(current: ConnectionState) -> ConnectionState {
        current == .disconnected ? .disconnected : .searching
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + Self.retryInterval) { [self] in findPeripheral() }
    }

    private func dropPeripheral() {
        peripheral = nil
        writeCharacteristic = nil
        connectStartedAt = nil
        verifiedPnP = nil
        lastBattery = nil
        finishPending(.failure(TransportError.notConnected))
        writes.reset()
        setState(.disconnected)
        scheduleRetry()
    }
}

extension CoreBluetoothTransport: CBCentralManagerDelegate {
    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            findPeripheral()
        default:
            peripheral = nil
            writeCharacteristic = nil
            connectStartedAt = nil
            finishPending(.failure(TransportError.notConnected))
            writes.reset()
            setState(.disconnected)
            mice = []
            for o in miceObservers.values { o.yield([]) }
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([VendorUUID.service, VendorUUID.batteryService, VendorUUID.deviceInfoService])
    }

    // Callbacks for a mouse we already switched away from are ignored.
    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        if peripheral.identifier == self.peripheral?.identifier { dropPeripheral() }
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        if peripheral.identifier == self.peripheral?.identifier { dropPeripheral() }
    }
}

extension CoreBluetoothTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            if service.uuid == VendorUUID.service {
                peripheral.discoverCharacteristics([VendorUUID.write, VendorUUID.notify], for: service)
            } else if service.uuid == VendorUUID.batteryService {
                peripheral.discoverCharacteristics([VendorUUID.batteryLevel], for: service)
            } else if service.uuid == VendorUUID.deviceInfoService {
                peripheral.discoverCharacteristics([VendorUUID.pnpID], for: service)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService,
                           error: Error?) {
        for c in service.characteristics ?? [] {
            switch c.uuid {
            case VendorUUID.write: writeCharacteristic = c
            case VendorUUID.notify: peripheral.setNotifyValue(true, for: c)
            case VendorUUID.batteryLevel:
                peripheral.readValue(for: c)
                peripheral.setNotifyValue(true, for: c)
            case VendorUUID.pnpID:
                peripheral.readValue(for: c)
            default: break
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        if characteristic.uuid == VendorUUID.notify, characteristic.isNotifying, writeCharacteristic != nil {
            connectStartedAt = nil
            setState(.connected(name: peripheral.name ?? "Pro Click Mini"))
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard writes.complete(), let error else { return }
        finishPending(.failure(TransportError.writeRejected(error.localizedDescription)))
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        guard let value = characteristic.value else { return }
        switch characteristic.uuid {
        case VendorUUID.notify:
            guard var p = pending else { return }
            let result = p.reassembler.feed([UInt8](value))
            pending = p
            switch result {
            case .payload(let bytes)?: finishPending(.success(bytes))
            case .failed(let status)?: finishPending(.failure(TransportError.status(status)))
            case nil: break
            }
        case VendorUUID.pnpID:
            guard let id = MouseSelection.parsePnPID([UInt8](value)) else { return }
            if MouseSelection.isProClickMini(vendor: id.vendor, product: id.product) {
                verifiedPnP = id
            } else {
                // Another Razer device sharing the vendor service: never talk to it again.
                rejected.insert(peripheral.identifier)
                abandon(peripheral)
            }
        case VendorUUID.batteryLevel:
            guard let level = value.first else { return }
            lastBattery = Int(level)
            for o in batteryObservers.values { o.yield(Int(level)) }
        default:
            break
        }
    }
}
