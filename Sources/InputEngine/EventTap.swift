import CoreGraphics
import Foundation

public enum EventTapError: Error, Equatable {
    /// Usually means the app lacks Accessibility permission.
    case couldNotCreate
}

/// A session-level, active CGEventTap on the current run loop. `handler` returns the event to
/// let it through, or nil to swallow it.
final class EventTap {
    typealias Handler = (CGEventType, CGEvent) -> CGEvent?

    let handler: Handler
    private var port: CFMachPort?
    private var source: CFRunLoopSource?
    /// Turns the tap on or off; replaceable in tests.
    lazy var setEnabled: (Bool) -> Void = { [weak self] enabled in
        if let port = self?.port { CGEvent.tapEnable(tap: port, enable: enabled) }
    }

    init(handler: @escaping Handler) {
        self.handler = handler
    }

    static let mask: CGEventMask = [CGEventType.scrollWheel, .leftMouseDown, .leftMouseUp, .rightMouseDown,
                                    .rightMouseUp, .otherMouseDown, .otherMouseUp]
        .reduce(0) { $0 | (1 << $1.rawValue) }

    var isRunning: Bool { port != nil }

    func start() throws {
        guard port == nil else { return }
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let port = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                           eventsOfInterest: Self.mask, callback: { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
            if tap.handleTapDisabled(type: type) { return Unmanaged.passUnretained(event) }
            return tap.handler(type, event).map { Unmanaged.passUnretained($0) }
        }, userInfo: refcon) else { throw EventTapError.couldNotCreate }
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, port, 0)
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        self.port = port
        self.source = source
        setEnabled(true)
    }

    func stop() {
        guard let port else { return }
        setEnabled(false)
        if let source { CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes) }
        CFMachPortInvalidate(port)
        self.port = nil
        self.source = nil
    }

    /// macOS disables a tap that is slow or when the user toggles secure input; turn it back on.
    func handleTapDisabled(type: CGEventType) -> Bool {
        guard type == .tapDisabledByTimeout || type == .tapDisabledByUserInput else { return false }
        setEnabled(true)
        return true
    }
}
