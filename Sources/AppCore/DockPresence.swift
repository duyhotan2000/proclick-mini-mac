/// The app lives in the menu bar, but shows a Dock icon while any of its windows is open.
public struct DockPresence: Sendable {
    private var open: Set<String> = []

    public init() {}

    public var showsInDock: Bool { !open.isEmpty }

    public mutating func opened(_ window: String) { open.insert(window) }
    public mutating func closed(_ window: String) { open.remove(window) }
}
