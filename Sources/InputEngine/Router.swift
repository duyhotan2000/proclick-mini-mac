import Foundation

public enum RoutedInput: Equatable, Sendable {
    /// `pan` uses the HID sign (negative = tilt left), not the CGEvent delta, which
    /// "natural scrolling" may invert.
    case horizontalScroll(pan: Int, at: TimeInterval)
    case button(ButtonID, down: Bool)
}

public enum RouteOutcome: Equatable, Sendable {
    case pass
    case consume
    case consumeAndRun(Action)
}

/// Decides what happens to one input event. Only events from the Pro Click Mini (`tagged`)
/// are ever consumed. `frontApp` is the frontmost app's bundle id: apps that ignore mouse
/// buttons 4/5 get pass-through side buttons as Back/Forward shortcuts instead.
public func route(_ input: RoutedInput, tagged: Bool, table: MappingTable,
                  debouncer: inout TiltDebouncer, frontApp: String? = nil) -> RouteOutcome {
    guard tagged else { return .pass }
    switch input {
    case .horizontalScroll(let pan, let time):
        guard pan != 0 else { return .pass }
        let action = table.action(for: pan < 0 ? .tiltLeft : .tiltRight)
        if action == .passThrough { return .pass }
        guard debouncer.handle(pan: pan, at: time) != nil, action != .disabled else { return .consume }
        return .consumeAndRun(action)
    case .button(let id, let down):
        var action = table.action(for: id)
        if action == .passThrough, let frontApp, BackForward.appsIgnoringSideButtons.contains(frontApp) {
            action = id == .button4 ? .back : id == .button5 ? .forward : action
        }
        if action == .passThrough { return .pass }
        return down && action != .disabled ? .consumeAndRun(action) : .consume
    }
}
