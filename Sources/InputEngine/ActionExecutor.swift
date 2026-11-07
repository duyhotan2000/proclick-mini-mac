import AppKit
import CoreGraphics

public enum DPIStep: Sendable {
    case up, down, cycle
}

/// Value written to `eventSourceUserData` on every event we synthesize, so our own event
/// tap never re-processes them.
public let syntheticEventMarker: Int64 = 0x5052_434C  // "PRCL"

/// Performs `Action`s. Call on the main thread.
public final class ActionExecutor: @unchecked Sendable {
    public var spaces: SpaceSwitcher
    let dpi: (@Sendable (DPIStep) -> Void)?

    public init(spaces: SpaceSwitcher, dpi: (@Sendable (DPIStep) -> Void)? = nil) {
        self.spaces = spaces
        self.dpi = dpi
    }

    public func run(_ action: Action) {
        switch action {
        case .passThrough, .disabled: break
        case .leftClick: click(.left)
        case .rightClick: click(.right)
        case .middleClick: click(.center)
        case .back: click(.center, buttonNumber: 3)
        case .forward: click(.center, buttonNumber: 4)
        case .previousDesktop: spaces.switchSpace(.left)
        case .nextDesktop: spaces.switchSpace(.right)
        case .missionControl: openApp("com.apple.exposelauncher")
        case .appExpose: KeyPoster.press(keyCode: 125, flags: .maskControl)  // Ctrl+↓
        case .showDesktop: KeyPoster.press(keyCode: 103)  // F11
        case .apps: openApp("com.apple.apps.launcher")
        case .shortcut(let keyCode, let modifiers):
            KeyPoster.press(keyCode: keyCode, flags: CGEventFlags(rawValue: modifiers))
        case .dpiUp: dpi?(.up)
        case .dpiDown: dpi?(.down)
        case .dpiCycle: dpi?(.cycle)
        case .media(let key): MediaKeyPoster.press(key)
        }
    }

    private func openApp(_ bundleID: String) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private func click(_ button: CGMouseButton, buttonNumber: Int64? = nil) {
        let location = CGEvent(source: nil)?.location ?? .zero
        let types: (CGEventType, CGEventType) = switch button {
        case .left: (.leftMouseDown, .leftMouseUp)
        case .right: (.rightMouseDown, .rightMouseUp)
        default: (.otherMouseDown, .otherMouseUp)
        }
        for type in [types.0, types.1] {
            guard let e = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: location,
                                  mouseButton: button) else { continue }
            if let buttonNumber { e.setIntegerValueField(.mouseEventButtonNumber, value: buttonNumber) }
            e.setIntegerValueField(.eventSourceUserData, value: syntheticEventMarker)
            e.post(tap: .cgSessionEventTap)
        }
    }
}

/// Media keys are NX_SYSDEFINED events (subtype 8) carrying an NX key code.
enum MediaKeyPoster {
    static func nxKey(_ key: MediaKey) -> Int {
        switch key {
        case .volumeUp: 0       // NX_KEYTYPE_SOUND_UP
        case .volumeDown: 1     // NX_KEYTYPE_SOUND_DOWN
        case .mute: 7           // NX_KEYTYPE_MUTE
        case .playPause: 16     // NX_KEYTYPE_PLAY
        case .next: 17          // NX_KEYTYPE_NEXT
        case .previous: 18      // NX_KEYTYPE_PREVIOUS
        }
    }

    static func press(_ key: MediaKey) {
        for down in [true, false] {
            let data1 = (nxKey(key) << 16) | ((down ? 0xA : 0xB) << 8)
            NSEvent.otherEvent(with: .systemDefined, location: .zero,
                               modifierFlags: NSEvent.ModifierFlags(rawValue: down ? 0xA00 : 0xB00),
                               timestamp: 0, windowNumber: 0, context: nil, subtype: 8, data1: data1, data2: -1)?
                .cgEvent?.post(tap: .cghidEventTap)
        }
    }
}
