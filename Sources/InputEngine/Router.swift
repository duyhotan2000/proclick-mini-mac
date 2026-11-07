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
/// are ever consumed.
public func route(_ input: RoutedInput, tagged: Bool, table: MappingTable,
                  debouncer: inout TiltDebouncer) -> RouteOutcome {
    guard tagged else { return .pass }
    switch input {
    case .horizontalScroll(let pan, let time):
        guard pan != 0 else { return .pass }
        let action = table.action(for: pan < 0 ? .tiltLeft : .tiltRight)
        if action == .passThrough { return .pass }
        guard debouncer.handle(pan: pan, at: time) != nil, action != .disabled else { return .consume }
        return .consumeAndRun(action)
    case .button(let id, let down):
        let action = table.action(for: id)
        if action == .passThrough { return .pass }
        return down && action != .disabled ? .consumeAndRun(action) : .consume
    }
}
