import AppKit
import CoreGraphics
import Foundation

/// Watches mouse events system-wide and applies `table` to the ones that come from the
/// Pro Click Mini. Start and use it on the main thread.
public final class InputEngine {
    /// How recently the mouse must have reported a HID value for an event to count as its own.
    public static let tagWindow: TimeInterval = 0.05

    public var table: MappingTable = .default
    /// Called for every classified event (for logging).
    public var onEvent: ((RoutedInput, _ tagged: Bool, RouteOutcome) -> Void)?

    let tagger: DeviceTagger
    let executor: ActionExecutor
    private var debouncer = TiltDebouncer()
    private var tap: EventTap?

    public init(tagger: DeviceTagger, executor: ActionExecutor) {
        self.tagger = tagger
        self.executor = executor
    }

    public var isRunning: Bool { tap?.isRunning ?? false }

    public func start() throws {
        guard !isRunning else { return }
        try tagger.start()
        let tap = EventTap { [unowned self] type, event in self.handle(type, event) }
        do {
            try tap.start()
        } catch {
            tagger.stop()
            throw error
        }
        self.tap = tap
    }

    public func stop() {
        tap?.stop()
        tap = nil
        tagger.stop()
    }

    private func handle(_ type: CGEventType, _ event: CGEvent) -> CGEvent? {
        if event.getIntegerValueField(.eventSourceUserData) == syntheticEventMarker { return event }
        guard let (input, tagged) = classify(type, event) else { return event }
        let outcome = route(input, tagged: tagged, table: table, debouncer: &debouncer,
                            frontApp: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
        onEvent?(input, tagged, outcome)
        switch outcome {
        case .pass: return event
        case .consume: return nil
        case .consumeAndRun(let action):
            // Never do slow work inside the tap callback, or macOS disables the tap.
            let executor = executor
            DispatchQueue.main.async { executor.run(action) }
            return nil
        }
    }

    private func classify(_ type: CGEventType, _ event: CGEvent) -> (RoutedInput, Bool)? {
        switch type {
        case .scrollWheel:
            guard event.getIntegerValueField(.scrollWheelEventDeltaAxis2) != 0,
                  event.getIntegerValueField(.scrollWheelEventIsContinuous) == 0 else { return nil }
            // Use the HID sign: the CGEvent delta flips with "natural scrolling".
            guard let pan = tagger.lastPan(within: Self.tagWindow) else {
                return (.horizontalScroll(pan: 0, at: tagger.clock()), false)
            }
            return (.horizontalScroll(pan: pan.value, at: tagger.clock()), true)
        case .leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp:
            let hidButton = Int(event.getIntegerValueField(.mouseEventButtonNumber)) + 1
            guard let id = ButtonID(hidButton: hidButton) else { return nil }
            let down = [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(type)
            let tagged = tagger.lastButton(within: Self.tagWindow)?.usage == hidButton
            return (.button(id, down: down), tagged)
        default:
            return nil
        }
    }
}
