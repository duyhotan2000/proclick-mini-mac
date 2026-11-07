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

/// `route` plus the state it needs across events: tilt debouncing, and which button presses
/// were swallowed, so each release is handled exactly like its press. Tagging the press and
/// the release separately could otherwise swallow a release whose press reached the app,
/// leaving that button stuck down system-wide.
public struct InputRouter: Sendable {
    public var table: MappingTable
    var debouncer = TiltDebouncer()
    var swallowedPresses: Set<ButtonID> = []

    public init(table: MappingTable) {
        self.table = table
    }

    public mutating func route(_ input: RoutedInput, tagged: Bool, frontApp: String? = nil) -> RouteOutcome {
        if case .button(let id, down: false) = input {
            return swallowedPresses.remove(id) != nil ? .consume : .pass
        }
        let outcome = routeEvent(input, tagged: tagged, table: table, debouncer: &debouncer, frontApp: frontApp)
        if case .button(let id, down: true) = input, outcome != .pass {
            swallowedPresses.insert(id)
        }
        return outcome
    }
}

/// The free `route`, reachable from inside `InputRouter.route`, which shadows its name.
private func routeEvent(_ input: RoutedInput, tagged: Bool, table: MappingTable, debouncer: inout TiltDebouncer,
                        frontApp: String?) -> RouteOutcome {
    route(input, tagged: tagged, table: table, debouncer: &debouncer, frontApp: frontApp)
}
