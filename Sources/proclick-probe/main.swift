// proclick-probe: hardware checks and recovery for the Razer Pro Click Mini.
import Foundation
import InputEngine
import RazerBLE

let usage = """
    usage: proclick-probe <command>
      read                               print the mouse's DPI stages, sleep timer and battery
      write-sleep <seconds> [--yes]      set the sleep timer (60–900)
      write-dpi <active> <dpi,...> [--yes]
                                         set DPI stages; <active> is the 0-based stage index
      restore-original [--yes]           write back the settings first read on 2026-11-06
      restore-factory [--yes]            write Razer's factory defaults (active 1600, sleep 300 s)
      snapshots                          list backups saved before each write
      hid-capture <seconds>              print the mouse's raw HID values (buttons, wheel, tilt)
      space next|prev [--keys]           switch one desktop (swipe animation, or Ctrl+arrow with --keys)
      run-engine                         run the tilt/button engine with default mappings until Ctrl+C
    Write commands print the planned bytes and change nothing unless --yes is given.
    --force writes the command's field even if its value is unchanged (to test a write with known-good values).
    """

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func connect() async -> (CoreBluetoothTransport, MouseClient) {
    let transport = CoreBluetoothTransport()
    do {
        try await transport.waitUntilConnected(timeout: 15)
    } catch {
        fail("Pro Click Mini not found over Bluetooth. Is it on, paired and connected?")
    }
    return (transport, MouseClient(transport: transport))
}

func describe(_ s: MouseState) -> String {
    let stages = s.dpi.stages.map { String($0.x) }.joined(separator: ",")
    return """
        dpi: active=\(s.dpi.activeID) stages=\(stages) marker=\(s.dpi.marker)
        sleep: \(s.sleepSeconds)s
        """
}

func describe(_ outcome: WriteOutcome) -> String {
    switch outcome {
    case .applied(let s): return "applied\n" + describe(s)
    case .notApplied(let reason): return "not applied: \(reason)"
    case .rolledBack(let reason, let restored): return "rolledBack: \(reason)\n" + describe(restored)
    case .rollbackFailed(let reason, let snapshot): return "rollbackFailed: \(reason)\nbackup: \(snapshot.path)"
    }
}

func hexString(_ bytes: [UInt8]) -> String { bytes.map { String(format: "%02x", $0) }.joined(separator: " ") }

/// Shows what a write would send, or performs it when `--yes` was passed.
@MainActor
func runWrite(forcing field: MouseClient.Field? = nil, _ makeTarget: (MouseState) -> MouseState) async {
    let (_, client) = await connect()
    let current: MouseState
    do { current = try await client.readState() } catch { fail("read failed: \(error)") }
    let target = makeTarget(current)
    let force: Set<MouseClient.Field> = forced ? Set([field].compactMap { $0 }) : []
    guard confirmed else {
        let wanted = MouseClient.merge(target, onto: current)
        print("current:\n" + describe(current) + "\nplanned:\n" + describe(wanted))
        let fields = MouseClient.changedFields(current, wanted).union(force)
        if fields.contains(.dpi) {
            print("would write \(Key.dpiTableWrite): \(hexString(wanted.dpi.encodeForWrite()))")
        }
        if fields.contains(.sleep) {
            print("would write \(Key.sleepWrite): \(hexString([UInt8(wanted.sleepSeconds & 0xFF), UInt8(wanted.sleepSeconds >> 8)]))")
        }
        fail("dry run: add --yes to write", code: 2)
    }
    let outcome = await client.apply(target, force: force)
    print(describe(outcome))
    if case .applied = outcome { return }
    exit(1)
}

/// Runs the main run loop (HID callbacks, event taps) for `seconds`.
func spinRunLoop(seconds: Double) {
    CFRunLoopRunInMode(.defaultMode, seconds, false)
}

let confirmed = CommandLine.arguments.contains("--yes")
let forced = CommandLine.arguments.contains("--force")
let args = Array(CommandLine.arguments.dropFirst()).filter { !["--yes", "--force", "--keys"].contains($0) }

switch args.first {
case "read":
    let (transport, client) = await connect()
    do {
        print(describe(try await client.readState()))
        let raw = try await client.readBatteryRaw()
        print("battery: \(raw)/255 (\(Int((Double(raw) * 100 / 255).rounded()))%)")
        try await Task.sleep(for: .milliseconds(500))  // let the PnP ID read finish
        if let pnp = transport.pnpID {
            print(String(format: "pnp: vendor=0x%04X product=0x%04X", pnp.vendor, pnp.product))
        } else {
            print("pnp: not read")
        }
    } catch {
        fail("read failed: \(error)")
    }
case "write-sleep":
    guard args.count == 2, let seconds = UInt16(args[1]) else { fail(usage, code: 2) }
    await runWrite(forcing: .sleep) { var s = $0; s.sleepSeconds = seconds; return s }
case "write-dpi":
    guard args.count == 3, let active = Int(args[1]) else { fail(usage, code: 2) }
    let values = args[2].split(separator: ",").compactMap { UInt16($0) }
    guard !values.isEmpty, (0..<values.count).contains(active) else { fail(usage, code: 2) }
    await runWrite(forcing: .dpi) { current in
        var s = current
        s.dpi.stages = values.enumerated().map { DPIStage(id: UInt8($0.offset + 1), x: $0.element, y: $0.element) }
        s.dpi.activeID = UInt8(active + 1)  // ids 1…n here; merge() maps them onto the mouse's ids
        return s
    }
case "restore-original":
    await runWrite { _ in Defaults.baseline }
case "restore-factory":
    await runWrite { _ in Defaults.factory }
case "snapshots":
    do {
        for url in try SnapshotStore.default.list() { print(url.path) }
    } catch {
        fail("couldn't list snapshots: \(error)")
    }
case "hid-capture":
    guard args.count == 2, let seconds = Double(args[1]) else { fail(usage, code: 2) }
    let tagger = DeviceTagger()
    let start = monotonicNow()
    tagger.onValue = { v in
        // Skip pointer motion (Generic Desktop X/Y); it would drown out everything else.
        if v.usagePage == 0x01 && (v.usage == 0x30 || v.usage == 0x31) { return }
        let ms = Int((v.timestamp - start) * 1000)
        print(String(format: "t=%6d page=0x%02X usage=0x%03X value=%d", ms, v.usagePage, v.usage, v.value))
        fflush(stdout)
    }
    do { try tagger.start() } catch { fail("couldn't open the mouse's HID device: \(error) (grant Input Monitoring?)") }
    print("capturing for \(Int(seconds)) s…"); fflush(stdout)
    spinRunLoop(seconds: seconds)
case "space":
    guard args.count == 2, ["next", "prev"].contains(args[1]) else { fail(usage, code: 2) }
    let keys = CommandLine.arguments.contains("--keys")
    let switcher = SpaceSwitcher(method: keys ? .controlArrow : .dockSwipe)
    switcher.switchSpace(args[1] == "next" ? .right : .left)
    spinRunLoop(seconds: 0.8)  // let the delayed end-event re-sends go out
case "run-engine":
    if KarabinerCheck.grabsProClick() {
        print("warning: Karabiner-Elements is set to modify the Pro Click Mini; tilts may not be detected")
    }
    let engine = InputEngine(tagger: DeviceTagger(), executor: ActionExecutor(spaces: SpaceSwitcher()))
    engine.onEvent = { input, tagged, outcome in
        print("\(input) tagged=\(tagged) → \(outcome)"); fflush(stdout)
    }
    do { try engine.start() } catch {
        fail("couldn't start the engine: \(error) (grant Accessibility and Input Monitoring?)")
    }
    print("engine running; Ctrl+C to stop"); fflush(stdout)
    while true { spinRunLoop(seconds: 3600) }
default:
    fail(usage, code: 2)
}
