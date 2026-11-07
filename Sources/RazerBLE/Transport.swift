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

    private struct Pending {
        var reassembler: Reassembler
        let continuation: CheckedContinuation<[UInt8], Error>
        let timeout: DispatchWorkItem
    }

    public override init() {
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
                for chunk in requestWrites(req: req, key: key, payload: payload) {
                    peripheral.writeValue(Data(chunk), for: writeCharacteristic, type: .withResponse)
                }
            }
        }
    }

    private func finishPending(_ result: Result<[UInt8], Error>) {
        guard let p = pending else { return }
        pending = nil
        p.timeout.cancel()
        p.continuation.resume(with: result)
    }

    // MARK: Connection

    private func setState(_ new: ConnectionState) {
        guard new != state else { return }
        state = new
        for o in stateObservers.values { o.yield(new) }
    }

    private func findPeripheral() {
        retryScheduled = false
        guard central.state == .poweredOn, peripheral == nil else { return }
        if let p = central.retrieveConnectedPeripherals(withServices: [VendorUUID.service]).first {
            peripheral = p
            p.delegate = self
            central.connect(p)
        } else {
            setState(.searching)
            scheduleRetry()
        }
    }

    private func scheduleRetry() {
        guard !retryScheduled else { return }
        retryScheduled = true
        queue.asyncAfter(deadline: .now() + Self.retryInterval) { [self] in findPeripheral() }
    }

    private func dropPeripheral() {
        peripheral = nil
        writeCharacteristic = nil
        finishPending(.failure(TransportError.notConnected))
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
            finishPending(.failure(TransportError.notConnected))
            setState(.disconnected)
        }
    }

    public func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([VendorUUID.service, VendorUUID.batteryService])
    }

    public func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        dropPeripheral()
    }

    public func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral,
                               error: Error?) {
        dropPeripheral()
    }
}

extension CoreBluetoothTransport: CBPeripheralDelegate {
    public func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        for service in peripheral.services ?? [] {
            if service.uuid == VendorUUID.service {
                peripheral.discoverCharacteristics([VendorUUID.write, VendorUUID.notify], for: service)
            } else if service.uuid == VendorUUID.batteryService {
                peripheral.discoverCharacteristics([VendorUUID.batteryLevel], for: service)
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
            default: break
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didUpdateNotificationStateFor characteristic: CBCharacteristic,
                           error: Error?) {
        if characteristic.uuid == VendorUUID.notify, characteristic.isNotifying, writeCharacteristic != nil {
            setState(.connected(name: peripheral.name ?? "Pro Click Mini"))
        }
    }

    public func peripheral(_ peripheral: CBPeripheral, didWriteValueFor characteristic: CBCharacteristic,
                           error: Error?) {
        if let error { finishPending(.failure(TransportError.writeRejected(error.localizedDescription))) }
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
        case VendorUUID.batteryLevel:
            guard let level = value.first else { return }
            lastBattery = Int(level)
            for o in batteryObservers.values { o.yield(Int(level)) }
        default:
            break
        }
    }
}
