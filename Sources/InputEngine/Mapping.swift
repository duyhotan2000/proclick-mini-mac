import Foundation

/// The Pro Click Mini's seven remappable inputs.
public enum ButtonID: String, Codable, CaseIterable, Sendable, CodingKeyRepresentable {
    case left, right, wheel, tiltLeft, tiltRight, button4, button5

    /// HID Button-page usage → button (docs/hid-capture.md). Tilts arrive as AC Pan, not buttons.
    public init?(hidButton: Int) {
        switch hidButton {
        case 1: self = .left
        case 2: self = .right
        case 3: self = .wheel
        case 4: self = .button4
        case 5: self = .button5
        default: return nil
        }
    }
}

public enum MediaKey: String, Codable, CaseIterable, Sendable {
    case playPause, next, previous, volumeUp, volumeDown, mute
}

public enum Action: Codable, Equatable, Sendable {
    case passThrough
    case disabled
    case leftClick, rightClick, middleClick
    case back, forward
    case previousDesktop, nextDesktop
    case missionControl, appExpose, showDesktop, apps
    case shortcut(keyCode: UInt16, modifiers: UInt64)
    case dpiUp, dpiDown, dpiCycle
    case media(MediaKey)
}

public struct MappingTable: Codable, Equatable, Sendable {
    public var actions: [ButtonID: Action]

    public init(actions: [ButtonID: Action]) {
        self.actions = actions
    }

    public static let `default` = MappingTable(actions: [.tiltLeft: .previousDesktop, .tiltRight: .nextDesktop])

    public func action(for button: ButtonID) -> Action {
        actions[button] ?? .passThrough
    }
}
