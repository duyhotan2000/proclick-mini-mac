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

/// Listens to the Pro Click Mini's raw HID values (without seizing the device), so the
/// event tap can tell its events apart from the trackpad's and other mice.
public final class DeviceTagger: @unchecked Sendable {
    public let vendorID: Int
    public let productID: Int
    public var onValue: (@Sendable (HIDValue) -> Void)?

    let clock: @Sendable () -> TimeInterval
    private var manager: IOHIDManager?

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
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw StartError.openFailed(result) }
        self.manager = manager
    }

    public func stop() {
        guard let manager else { return }
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    private func receive(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let v = HIDValue(usagePage: Int(IOHIDElementGetUsagePage(element)), usage: Int(IOHIDElementGetUsage(element)),
                         value: IOHIDValueGetIntegerValue(value), timestamp: clock())
        onValue?(v)
    }
}
