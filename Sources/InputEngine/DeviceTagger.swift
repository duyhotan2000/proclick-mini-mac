import Foundation
import IOKit.hid

/// One HID element value reported by the Pro Click Mini.
public struct HIDValue: Sendable {
    public let usagePage: Int
    public let usage: Int
    public let value: Int
    /// Seconds on the tagger's clock.
    public let timestamp: TimeInterval
}

/// Monotonic seconds since boot.
public func monotonicNow() -> TimeInterval {
    TimeInterval(clock_gettime_nsec_np(CLOCK_UPTIME_RAW)) / 1_000_000_000
}

/// Converts mach absolute time (the clock HID timestamps and `monotonicNow` use) to seconds.
func machSeconds(_ ticks: UInt64) -> TimeInterval {
    var timebase = mach_timebase_info_data_t()
    mach_timebase_info(&timebase)
    return TimeInterval(ticks) * TimeInterval(timebase.numer) / TimeInterval(timebase.denom) / 1_000_000_000
}

/// Listens to the Pro Click Mini's raw HID values (without seizing the device), so the
/// event tap can tell its events apart from the trackpad's and other mice.
public final class DeviceTagger: @unchecked Sendable {
    public let vendorID: Int
    public let productID: Int
    public var onValue: (@Sendable (HIDValue) -> Void)?

    let clock: @Sendable () -> TimeInterval
    private var manager: IOHIDManager?
    private let lock = NSLock()
    private var pan: HIDValue?
    private var button: HIDValue?

    public init(vendorID: Int = 0x1532, productID: Int = 0x009B,
                clock: @escaping @Sendable () -> TimeInterval = monotonicNow) {
        self.vendorID = vendorID
        self.productID = productID
        self.clock = clock
    }

    public enum StartError: Error, Equatable {
        case openFailed(Int32)
    }

    /// Starts listening on the current run loop.
    public func start() throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        IOHIDManagerSetDeviceMatching(manager, [
            kIOHIDVendorIDKey: vendorID,
            kIOHIDProductIDKey: productID,
        ] as CFDictionary)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, { context, _, _, value in
            guard let context else { return }
            let tagger = Unmanaged<DeviceTagger>.fromOpaque(context).takeUnretainedValue()
            tagger.receive(value)
        }, context)
        // Same modes as the event tap, so HID values never queue up behind it.
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw StartError.openFailed(result) }
        self.manager = manager
    }

    public func stop() {
        guard let manager else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    /// The last non-zero tilt (AC Pan) value, if it arrived within `window` seconds.
    public func lastPan(within window: TimeInterval) -> HIDValue? {
        lock.withLock { fresh(pan, within: window) }
    }

    /// The last button press or release, if it arrived within `window` seconds.
    public func lastButton(within window: TimeInterval) -> HIDValue? {
        lock.withLock { fresh(button, within: window) }
    }

    private func fresh(_ v: HIDValue?, within window: TimeInterval) -> HIDValue? {
        guard let v, clock() - v.timestamp <= window else { return nil }
        return v
    }

    private func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        // Stamp with when the mouse reported it, not when we got to it.
        record(HIDValue(usagePage: Int(IOHIDElementGetUsagePage(element)), usage: Int(IOHIDElementGetUsage(element)),
                        value: IOHIDValueGetIntegerValue(value),
                        timestamp: machSeconds(IOHIDValueGetTimeStamp(value))))
    }

    func record(_ v: HIDValue) {
        lock.withLock {
            // Pan = 0 rides on every motion report; only a real tilt tags.
            if v.usagePage == 0x0C && v.usage == 0x238 && v.value != 0 { pan = v }
            if v.usagePage == 0x09 { button = v }
        }
        onValue?(v)
    }
}
