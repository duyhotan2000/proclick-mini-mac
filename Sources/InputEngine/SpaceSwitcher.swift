import CoreGraphics
import Foundation

public enum SpaceMethod: String, Codable, CaseIterable, Sendable {
    /// Synthetic Dock-swipe gesture: the real three-finger-swipe slide animation.
    case dockSwipe
    /// Ctrl+←/→. Needs "Move left/right a space" enabled in Keyboard Shortcuts › Mission Control.
    case controlArrow
}

/// Moves one desktop (Space) left or right.
public struct SpaceSwitcher: Sendable {
    public var method: SpaceMethod

    public init(method: SpaceMethod = .dockSwipe) {
        self.method = method
    }

    public func switchSpace(_ direction: TiltEvent) {
        switch method {
        case .dockSwipe: DockSwipe.swipe(direction)
        case .controlArrow: KeyPoster.press(keyCode: direction == .left ? 123 : 124, flags: .maskControl)
        }
    }
}

/// Synthetic Dock-swipe events, ported from Mac Mouse Fix
/// (github.com/noah-nuebling/mac-mouse-fix, Helper/Core/Touch/TouchSimulator.m,
/// `postDockSwipeEventWithDelta:type:phase:invertedFromDevice:`, pre-macOS-27 path).
/// macOS 27 ignores these CGEvent fields and needs an attached IOHIDEvent instead.
enum DockSwipe {
    // ---- Private CGEvent fields (from TouchSimulator.m) ----
    static let fieldEventType = CGEventField(rawValue: 55)!       // 29 = gesture, 30 = "magnify"/dock
    static let fieldSubtype = CGEventField(rawValue: 110)!        // kIOHIDEventTypeDockSwipe
    static let fieldPhase = CGEventField(rawValue: 132)!
    static let fieldPhase2 = CGEventField(rawValue: 134)!
    static let fieldOriginOffset = CGEventField(rawValue: 124)!
    static let fieldOriginOffsetBits = CGEventField(rawValue: 135)!  // Float32 bits in an Int64
    static let field41 = CGEventField(rawValue: 41)!               // always 33231
    static let fieldTypeBits = CGEventField(rawValue: 119)!
    static let fieldTypeBits2 = CGEventField(rawValue: 139)!
    static let fieldMotion = CGEventField(rawValue: 123)!
    static let fieldMotion2 = CGEventField(rawValue: 165)!
    static let fieldInverted = CGEventField(rawValue: 136)!
    static let fieldExitSpeed = CGEventField(rawValue: 129)!
    static let fieldExitSpeed2 = CGEventField(rawValue: 130)!

    static let kIOHIDEventTypeDockSwipe = 23.0
    static let motionHorizontal = 1.0
    static let horizontalTypeBits = 1.401298464324817e-45  // Float32 bit pattern 0x00000001
    static let value41 = 33231.0

    enum Phase: Double {
        case began = 1, changed = 2, ended = 4, cancelled = 8
    }

    /// Negative origin offset moves to the Space on the left (verified on macOS 26.7.1).
    /// Flip the sign here if a future macOS reverses it.
    static func swipe(_ direction: TiltEvent) {
        let sign: Double = direction == .left ? -1 : 1
        // A short drag that ends with velocity in the same direction commits one Space.
        let deltas = [0.05, 0.1, 0.2].map { $0 * sign }
        post(offset: deltas[0], phase: .began, exitSpeed: 0)
        var offset = deltas[0]
        for d in deltas.dropFirst() {
            offset += d
            post(offset: offset, phase: .changed, exitSpeed: 0)
        }
        let finalOffset = offset, exitSpeed = deltas.last! * 100
        let end: @Sendable () -> Void = { post(offset: finalOffset, phase: .ended, exitSpeed: exitSpeed) }
        end()
        // Mac Mouse Fix re-sends the end event: under load the first one is sometimes ignored.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: end)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: end)
    }

    static func post(offset: Double, phase: Phase, exitSpeed: Double) {
        guard let e30 = CGEvent(source: nil), let e29 = CGEvent(source: nil) else { return }
        e29.setDoubleValueField(fieldEventType, value: 29)
        e29.setDoubleValueField(field41, value: value41)

        e30.setDoubleValueField(fieldEventType, value: 30)
        e30.setDoubleValueField(fieldSubtype, value: kIOHIDEventTypeDockSwipe)
        e30.setDoubleValueField(fieldPhase, value: phase.rawValue)
        e30.setDoubleValueField(fieldPhase2, value: phase.rawValue)
        e30.setDoubleValueField(fieldOriginOffset, value: offset)
        e30.setIntegerValueField(fieldOriginOffsetBits, value: Int64(Float32(offset).bitPattern))
        e30.setDoubleValueField(field41, value: value41)
        e30.setDoubleValueField(fieldTypeBits, value: horizontalTypeBits)
        e30.setDoubleValueField(fieldTypeBits2, value: horizontalTypeBits)
        e30.setDoubleValueField(fieldMotion, value: motionHorizontal)
        e30.setDoubleValueField(fieldMotion2, value: motionHorizontal)
        e30.setIntegerValueField(fieldInverted, value: 0)
        if phase == .ended || phase == .cancelled {
            e30.setDoubleValueField(fieldExitSpeed, value: exitSpeed)
            e30.setDoubleValueField(fieldExitSpeed2, value: exitSpeed)
        }
        e30.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        e29.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
        e30.post(tap: .cgSessionEventTap)
        e29.post(tap: .cgSessionEventTap)
    }
}

/// Posts synthetic key presses.
enum KeyPoster {
    static func press(keyCode: CGKeyCode, flags: CGEventFlags = []) {
        let source = CGEventSource(stateID: .hidSystemState)
        for down in [true, false] {
            guard let e = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: down) else { continue }
            e.flags = flags
            e.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            e.post(tap: .cgSessionEventTap)
        }
    }
}
