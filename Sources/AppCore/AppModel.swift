import CoreBluetooth
import Foundation
import InputEngine
import RazerBLE
import ServiceManagement

/// App state shared by the menu bar and the settings window.
@MainActor
public final class AppModel: ObservableObject {
    @Published public private(set) var connection: ConnectionState = .searching
    @Published public private(set) var batteryPercent: Int?
    @Published public private(set) var state: MouseState?
    @Published public private(set) var mapping: MappingTable
    @Published public var spaceMethod: SpaceMethod {
        didSet {
            defaults.set(spaceMethod.rawValue, forKey: Self.spaceMethodKey)
            executor.spaces.method = spaceMethod
        }
    }
    @Published public private(set) var lastOutcome: WriteOutcome?
    @Published public private(set) var onboarding: OnboardingState = .ready
    @Published public private(set) var karabinerConflict = false
    @Published public private(set) var isWriting = false
    @Published public private(set) var launchAtLogin = false
    @Published public var lowBatteryAlerts: Bool {
        didSet { defaults.set(lowBatteryAlerts, forKey: Self.lowBatteryKey) }
    }

    static let mappingKey = "mapping.v1"
    static let spaceMethodKey = "spaceMethod"
    static let lowBatteryKey = "lowBatteryAlerts"

    let defaults: UserDefaults
    let executor: ActionExecutor
    let engine: InputEngine
    private var transport: CoreBluetoothTransport?
    private var client: MouseClient?
    private var tasks: [Task<Void, Never>] = []
    private var pollTimer: Timer?
    private var promptedInputMonitoring = false
    private var lowBattery = LowBatteryNotifier()

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let method = defaults.string(forKey: Self.spaceMethodKey).flatMap(SpaceMethod.init(rawValue:)) ?? .dockSwipe
        spaceMethod = method
        mapping = Self.loadMapping(defaults)
        lowBatteryAlerts = defaults.object(forKey: Self.lowBatteryKey) as? Bool ?? true
        executor = ActionExecutor(spaces: SpaceSwitcher(method: method))
        engine = InputEngine(tagger: DeviceTagger(), executor: executor)
        engine.table = mapping
    }

    static func loadMapping(_ defaults: UserDefaults) -> MappingTable {
        guard let data = defaults.data(forKey: mappingKey),
              let table = try? JSONDecoder().decode(MappingTable.self, from: data) else { return .default }
        return table
    }

    /// Connects to the mouse, starts the input engine once permitted, and keeps both up to date.
    public func start() {
        guard transport == nil else { return }
        let transport = CoreBluetoothTransport()
        self.transport = transport
        client = MouseClient(transport: transport)
        executor.dpi = { [weak self] step in Task { @MainActor in await self?.stepDPI(step) } }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        tasks.append(Task { [weak self] in
            for await c in transport.connectionState { await self?.connectionChanged(c) }
        })
        tasks.append(Task { [weak self] in
            for await p in transport.batteryPercent { self?.batteryChanged(p) }
        })
        _ = Permissions.accessibilityTrusted(prompt: true)
        updatePermissions()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.updatePermissions() }
        }
    }

    func updatePermissions() {
        let trusted = Permissions.accessibilityTrusted()
        var listening = Permissions.inputMonitoringGranted()
        if trusted && !listening && !promptedInputMonitoring {
            promptedInputMonitoring = true
            Permissions.requestInputMonitoring()
            listening = Permissions.inputMonitoringGranted()
        }
        onboarding = onboardingState(accessibilityTrusted: trusted, bluetooth: CBManager.authorization,
                                     poweredOn: transport?.isPoweredOn ?? false, inputMonitoring: listening)
        karabinerConflict = KarabinerCheck.grabsProClick()
        // The engine only needs Accessibility and Input Monitoring, not Bluetooth.
        switch engineChange(running: engine.isRunning, trusted: trusted, listening: listening) {
        case .start: try? engine.start()
        case .stop: engine.stop()
        case .none: break
        }
    }

    public func refresh() async {
        guard let client else { return }
        if let s = try? await client.readState() { state = s }
        if batteryPercent == nil, let raw = try? await client.readBatteryRaw() {
            batteryChanged(Int((Double(raw) * 100 / 255).rounded()))
        }
    }

    func connectionChanged(_ c: ConnectionState) async {
        connection = c
        if case .connected = c {
            await refresh()
        } else {
            // Don't show a stale battery level or DPI stages for a mouse that's gone.
            batteryPercent = nil
            state = nil
        }
    }

    func batteryChanged(_ percent: Int) {
        batteryPercent = percent
        if lowBattery.update(percent: percent) && lowBatteryAlerts {
            LowBatteryNotifier.post(percent: percent)
        }
    }

    public func apply(_ s: MouseState) async {
        await write { await $0.apply(s) }
    }

    public func restoreOriginal() async {
        await write { await $0.restoreOriginal() }
    }

    public func restoreFactory() async {
        await write { await $0.restoreFactory() }
    }

    private func write(_ op: (MouseClient) async -> WriteOutcome) async {
        guard let client, !isWriting else { return }
        isWriting = true
        defer { isWriting = false }
        let outcome = await op(client)
        lastOutcome = outcome
        switch outcome {
        case .applied(let s): state = s
        case .rolledBack(_, let restored): state = restored
        case .notApplied, .rollbackFailed: await refresh()
        }
    }

    /// Moves the active DPI stage (for buttons mapped to DPI actions).
    func stepDPI(_ step: DPIStep) async {
        guard var s = state, !s.dpi.stages.isEmpty else { return }
        let n = s.dpi.stages.count, i = s.dpi.activeIndex
        let next = switch step {
        case .up: min(i + 1, n - 1)
        case .down: max(i - 1, 0)
        case .cycle: (i + 1) % n
        }
        guard next != i else { return }
        s.dpi.activeID = s.dpi.stages[next].id
        await apply(s)
    }

    public func setAction(_ a: Action, for b: ButtonID) {
        var table = mapping
        table.actions[b] = a
        save(table)
    }

    public func resetMapping() {
        save(.default)
    }

    private func save(_ table: MappingTable) {
        mapping = table
        engine.table = table
        if let data = try? JSONEncoder().encode(table) { defaults.set(data, forKey: Self.mappingKey) }
    }

    public func setLaunchAtLogin(_ on: Bool) throws {
        defer { launchAtLogin = SMAppService.mainApp.status == .enabled }
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}
