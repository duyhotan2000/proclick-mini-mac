import AppKit
import InputEngine

extension ButtonID {
    var title: String {
        switch self {
        case .left: "Left button"
        case .right: "Right button"
        case .wheel: "Wheel click"
        case .tiltLeft: "Wheel tilt left"
        case .tiltRight: "Wheel tilt right"
        case .button4: "Side button (back)"
        case .button5: "Side button (forward)"
        }
    }

    /// What the button does when left untouched.
    var nativeTitle: String {
        switch self {
        case .left: "Left click"
        case .right: "Right click"
        case .wheel: "Middle click"
        case .tiltLeft, .tiltRight: "Scroll sideways"
        case .button4: "Back"
        case .button5: "Forward"
        }
    }
}

enum ActionCatalog {
    static let groups: [(title: String, actions: [Action])] = [
        ("Mouse", [.leftClick, .rightClick, .middleClick]),
        ("Navigation", [.back, .forward]),
        ("Desktop", [.previousDesktop, .nextDesktop]),
        ("System", [.missionControl, .appExpose, .showDesktop, .apps]),
        ("DPI", [.dpiUp, .dpiDown, .dpiCycle]),
        ("Media", MediaKey.allCases.map(Action.media)),
    ]

    static func title(_ action: Action, for button: ButtonID) -> String {
        switch action {
        case .passThrough: "Default (\(button.nativeTitle))"
        default: title(action)
        }
    }

    static func title(_ action: Action) -> String {
        switch action {
        case .passThrough: "Default"
        case .disabled: "Disabled"
        case .leftClick: "Left click"
        case .rightClick: "Right click"
        case .middleClick: "Middle click"
        case .back: "Back"
        case .forward: "Forward"
        case .previousDesktop: "Previous desktop"
        case .nextDesktop: "Next desktop"
        case .missionControl: "Mission Control"
        case .appExpose: "App windows (App Exposé)"
        case .showDesktop: "Show desktop"
        case .apps: "Apps"
        case .dpiUp: "DPI up"
        case .dpiDown: "DPI down"
        case .dpiCycle: "Cycle DPI stages"
        case .media(let key):
            switch key {
            case .playPause: "Play / pause"
            case .next: "Next track"
            case .previous: "Previous track"
            case .volumeUp: "Volume up"
            case .volumeDown: "Volume down"
            case .mute: "Mute"
            }
        case .shortcut(let keyCode, let modifiers): shortcutTitle(keyCode: keyCode, modifiers: modifiers)
        }
    }

    static func shortcutTitle(keyCode: UInt16, modifiers: UInt64) -> String {
        let flags = NSEvent.ModifierFlags(rawValue: UInt(modifiers))
        var s = ""
        if flags.contains(.control) { s += "⌃" }
        if flags.contains(.option) { s += "⌥" }
        if flags.contains(.shift) { s += "⇧" }
        if flags.contains(.command) { s += "⌘" }
        return s + (keyNames[keyCode] ?? "Key \(keyCode)")
    }

    /// US-layout names for virtual key codes (Carbon kVK_*).
    static let keyNames: [UInt16: String] = {
        var names: [UInt16: String] = [
            36: "↩", 48: "⇥", 49: "Space", 51: "⌫", 53: "⎋", 117: "⌦",
            123: "←", 124: "→", 125: "↓", 126: "↑", 115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
            122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6", 98: "F7", 100: "F8",
            101: "F9", 109: "F10", 103: "F11", 111: "F12",
        ]
        let ansi = "ASDFHGZXCV BQWERYT123465=97-80]OU[IP LJ'K;\\,/NM."
        for (i, ch) in ansi.enumerated() where ch != " " { names[UInt16(i)] = String(ch) }
        names[50] = "`"
        return names
    }()
}
