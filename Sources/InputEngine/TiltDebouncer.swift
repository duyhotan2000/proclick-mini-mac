import Foundation

public enum TiltEvent: Equatable, Sendable {
    case left, right
}

/// Turns the stream of AC Pan values a tilt produces into one event per tilt.
///
/// The mouse repeats ±1 every ~22 ms while the wheel is tilted (docs/hid-capture.md).
/// A gesture ends after `silenceWindow` without pan in its direction.
public struct TiltDebouncer: Sendable {
    public static let defaultSilenceWindow: TimeInterval = 0.25

    public var silenceWindow: TimeInterval
    private var direction: TiltEvent?
    private var lastPan: TimeInterval = -.infinity

    public init(silenceWindow: TimeInterval = TiltDebouncer.defaultSilenceWindow) {
        self.silenceWindow = silenceWindow
    }

    /// `pan` is the HID AC Pan value: negative = left, positive = right, 0 = no tilt.
    public mutating func handle(pan: Int, at time: TimeInterval) -> TiltEvent? {
        guard pan != 0 else { return nil }
        let event: TiltEvent = pan < 0 ? .left : .right
        let continuing = event == direction && time - lastPan < silenceWindow
        direction = event
        lastPan = time
        return continuing ? nil : event
    }
}
