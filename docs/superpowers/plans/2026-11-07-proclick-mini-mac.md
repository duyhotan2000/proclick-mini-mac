# Pro Click Mini for macOS Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a native macOS menu-bar app that:
- switches desktops when the Razer Pro Click Mini's wheel is tilted (one tilt
  moves one desktop),
- remaps the mouse's buttons on the Mac,
- reads and writes DPI stages, the sleep timer and battery over Bluetooth,
  with automatic rollback and reset commands.

**Architecture:**
- **`RazerBLE` library:**
  - Pure framing and parsing code.
  - A CoreBluetooth transport for the Razer vendor GATT service.
  - A `MouseClient` that does snapshot → write → verify → rollback.
- **`InputEngine` library:**
  - Tags HID events from the Pro Click Mini with IOHIDManager.
  - Intercepts those events with a CGEventTap.
  - Pure logic for tilt debouncing and button mapping.
  - Runs actions, including synthesized Dock-swipe desktop switching.
- **Executables on top:**
  - `proclick-probe`: a CLI for hardware checks and recovery.
  - `ProClickMini`: the SwiftUI app.

**Tech Stack:** Swift 6 (language mode 6), SwiftUI, CoreBluetooth, IOKit HID,
CoreGraphics event taps, ServiceManagement, UserNotifications, Swift Testing,
SwiftPM using Xcode's toolchain.

**Spec:** `docs/superpowers/specs/2026-11-06-proclick-mini-mac-design.md`.
Read it first, especially §5 (verified bytes) and §6 "Write safety and
recovery".

## Global Constraints

- **Platform:** macOS 14 minimum (`.macOS(.v14)`). Dev machine is macOS 26.7.1 on Apple Silicon.
- **Toolchain:** Xcode's (`xcode-select -p` must print `/Applications/Xcode.app/Contents/Developer`). The Command Line Tools copy of SwiftPM is broken.
- **No third-party dependencies.**
- **Device:** Bluetooth only. `ProClickM`, VID `0x1532` (5426), PID `0x009B` (155).
- **Vendor GATT UUIDs:**
  - service `52401523-F97C-7F90-0E7F-6C6F4E36DB1C`
  - write `52401524-…` (with response)
  - notify `52401525-…`
- **Request frame:** `[req, len, 00, 00, k0, k1, k2, k3] + payload`. Req IDs start at `0x30` and wrap. One exchange at a time.
- **Notify header:** `[req, len, 00, 00, 00, 00, 00, status]`; status `02` = OK, `03` = error, `05` = bad parameter. The payload is the following notify frames concatenated, truncated to `len`.
- **Writes:** only these keys may be written:
  - `05 04 00 00` (sleep, u16 LE seconds)
  - `0B 04 01 00` (DPI table, 38 bytes)
  - On-mouse button bind (`08 04 …`) is out of scope.
- **Value limits:**
  - DPI 100–12000 in steps of 50.
  - 1–5 stages.
  - Sleep timer 60–900 s.
- **Factory defaults:** stages 400/800/1600/3200/6400, active 1600, sleep 300 s.
- **Original baseline (2026-11-06):** active stage id 4 (3200), stages 400/800/1600/3200/6400 with ids 1–5, marker byte absent from the read (payload 36 bytes) and written as `00`, sleep 300 s.
- **Snapshot directory:** `~/Library/Application Support/ProClickMini/snapshots/`. Every snapshot is written to disk **before** its write is sent.
- **Tilt behavior:**
  - One tilt = one desktop.
  - Repeated pan in the same direction is swallowed until 250 ms of pan silence. This constant is tuned in Task 6.
  - Only events from the Pro Click Mini are intercepted.
- **Default mapping:** tilt left → previous desktop, tilt right → next desktop. Everything else passes through untouched.
- **Bundle:**
  - Bundle id `com.duyho.ProClickMini`, app name "ProClick Mini", `LSUIElement` = true.
  - `NSBluetoothAlwaysUsageDescription` = "ProClick Mini talks to your Razer Pro Click Mini over Bluetooth to read and change its settings."
- **Signing:** with the keychain identity "ProClick Mini Dev" when present; otherwise ad-hoc (`-`).
- **Hardware-checkpoint steps:** any step that writes to the real mouse requires the owner's confirmation in chat before it runs.

## Review Focus

1. **The mouse disconnects in the middle of an exchange** (sleep, power slider off, switched to another Bluetooth slot). Expected: the exchange times out after 2 s, rollback is attempted, the UI shows "Disconnected", nothing crashes, and the client reconnects when the mouse returns. Tests: Task 4 `writeTimesOutAndRollsBack` and Task 3 `transportFailsPendingOnDisconnect`.
2. **The trackpad scrolls horizontally while (or right after) the mouse is tilted.** Expected: trackpad events are never swallowed. Only events tagged to the Pro Click Mini are. Tests: Task 7 `untaggedPanPassesThrough` and Task 9 `tagExpiresAfterWindow`.
3. **macOS disables the event tap** (`tapDisabledByTimeout` / `tapDisabledByUserInput`). Expected: the tap is re-enabled immediately and input keeps working. Test: Task 9 `reenablesOnDisableEvent`.
4. **Accessibility permission is missing or revoked.** Expected: the app still shows battery and DPI settings, shows a banner with a button that opens System Settings › Privacy › Accessibility, and installs the tap as soon as permission is granted. Nothing crashes. Test: Task 10 `onboardingStateWithoutAccessibility`.
5. **The DPI read payload is one byte short** (the final marker is missing, as the spec notes), or the active byte is not one of the stage ids. Expected: parsing still succeeds and resolves the active stage by id, then by 1-based index, then by clamping. Tests: Task 2 `parsesTruncatedTable` and `activeResolutionFallbacks`.

---

## File Structure

```
Package.swift
Sources/RazerBLE/
  Frame.swift            request encoding, notify reassembly (pure)
  DPITable.swift         DPI table parse/encode (pure)
  MouseState.swift       MouseState, defaults, validation (pure)
  Transport.swift        VendorTransport protocol + CoreBluetooth impl
  MouseClient.swift      typed reads, snapshot/write/verify/rollback
  SnapshotStore.swift    JSON snapshots on disk
Sources/InputEngine/
  Mapping.swift          ButtonID, Action, MappingTable (pure, Codable)
  TiltDebouncer.swift    pure state machine
  DeviceTagger.swift     IOHIDManager: marks recent pan/buttons from the mouse
  EventTap.swift         CGEventTap, decides consume/pass via Router
  Router.swift           pure decision: (event kind, tagged?, mapping) → outcome
  SpaceSwitcher.swift    Dock-swipe synth + Ctrl+arrow fallback
  ActionExecutor.swift   runs Action values
  KarabinerCheck.swift   reads ~/.config/karabiner/karabiner.json
Sources/proclick-probe/main.swift
Sources/ProClickMini/
  ProClickMiniApp.swift  MenuBarExtra + Window scenes
  AppModel.swift         @MainActor ObservableObject gluing everything
  Permissions.swift      Accessibility/Bluetooth status + onboarding state
  Views/CustomizeTab.swift, PerformanceTab.swift, PowerTab.swift, MouseDiagram.swift, MenuBarView.swift
Resources/Info.plist
Tests/RazerBLETests/…, Tests/InputEngineTests/…, Tests/ProClickMiniTests/…
scripts/setup-signing.sh, scripts/build-app.sh
docs/device-baseline.json, docs/hid-capture.md
```

`ProClickMini` is an executable target. To make its non-UI logic testable,
move `AppModel`/`Permissions` logic into a small `AppCore` library target that
`ProClickMini` depends on. `Tests/ProClickMiniTests` tests `AppCore`.

---

### Task 0: Toolchain, repo and package skeleton

**Files:**
- Create: `Package.swift`, `.gitignore`, one placeholder source file per target, `Tests/RazerBLETests/SmokeTests.swift`

**Interfaces:**
- Produces: these targets:
  - libraries `RazerBLE`, `InputEngine` (depends on RazerBLE), `AppCore` (depends on both)
  - executables `proclick-probe` (depends on RazerBLE, InputEngine) and `ProClickMini` (depends on AppCore)
  - test targets `RazerBLETests`, `InputEngineTests`, `AppCoreTests`

- [ ] **Step 1:** Verify the toolchain.

  Run: `xcode-select -p && swift --version`
  Expected: `/Applications/Xcode.app/Contents/Developer`.

  If it prints `/Library/Developer/CommandLineTools`, stop and ask the owner to run:
  - `! sudo xcode-select -s /Applications/Xcode.app`
  - `! sudo xcodebuild -license accept`

- [ ] **Step 2:** `git init`. Add a `.gitignore` covering `.build/`, `.superpowers/`, `build/` and `*.app`.

- [ ] **Step 3:** Write `Package.swift`:
  - swift-tools-version 6.0
  - platforms `.macOS(.v14)`
  - the targets above

  Also write the smoke test `@Test func smoke() { #expect(true) }`.

- [ ] **Step 4:** Run `swift build && swift test`.
  Expected: build succeeds, and the output reads `Test run with 1 test passed`.

- [ ] **Step 5:** Commit the spec, the plan and the skeleton:

  `git add -A && git commit -m "chore: package skeleton, design and plan"`

---

### Task 1: Frame encoding and notify reassembly

**Files:**
- Create: `Sources/RazerBLE/Frame.swift`
- Test: `Tests/RazerBLETests/FrameTests.swift`

**Interfaces:**
- Produces:
  - `public struct Key: Hashable, Sendable { public let bytes: (UInt8,UInt8,UInt8,UInt8) }` with statics `dpiTable = 0B 84 01 00`, `dpiTableWrite = 0B 04 01 00`, `activeDPI = 0B 81 00 00`, `activeStages = 0B 82 00 00`, `sleep = 05 84 00 00`, `sleepWrite = 05 04 00 00`, `batteryRaw = 05 81 00 01`, `batteryStatus = 05 80 00 01`. Store as `[UInt8]` of count 4 if tuples get in the way of `Hashable`.
  - `public func encodeRequest(req: UInt8, key: Key, payload: [UInt8] = []) -> [UInt8]`
  - `public enum Status: UInt8 { case ok = 2, error = 3, badParam = 5 }`
  - `public struct Reassembler { public init(req: UInt8); public mutating func feed(_ frame: [UInt8]) -> Result? }`, where `public enum Result: Equatable { case payload([UInt8]); case failed(Status) }`
    - `feed` ignores frames until it sees a header whose byte 0 == req and whose byte 7 ∈ {2,3,5}.
    - It then collects later frames until it has `len` bytes.
    - It returns `.payload` (truncated to `len`) when complete, or `.failed` right away if status ≠ 2.
    - With `len == 0` it completes on the header itself.

- [ ] **Step 1: Write failing tests.** Use the bytes captured on 2026-11-06:

```swift
@Test func encodesReadRequest() {
  #expect(encodeRequest(req: 0x31, key: .dpiTable) == [0x31,0,0,0,0x0B,0x84,0x01,0x00])
}
@Test func encodesWriteRequestWithLength() {
  #expect(encodeRequest(req: 0x40, key: .sleepWrite, payload: [0x2C,0x01]) == [0x40,0x02,0,0,0x05,0x04,0,0,0x2C,0x01])
}
@Test func reassemblesDPITableFromCapture() {
  var r = Reassembler(req: 0x31)
  // stale frame from an earlier exchange must be ignored
  #expect(r.feed(hex("01 00 00 00 00 00 00 03 50 76 0f 8d 6e 04 98 fa 4b 2d 72 ed")) == nil)
  #expect(r.feed(hex("31 24 00 00 00 00 00 02 50 76 0f 8d 6e 04 98 fa 4b 2d 72 ed")) == nil)
  #expect(r.feed(hex("04 05 01 90 01 90 01 00 00 02 20 03 20 03 00 00 03 40 06 40")) == nil)
  #expect(r.feed(hex("06 00 00 04 80 0c 80 0c 00 00 05 00 19 00 19 00 03 40 06 40")) ==
    .payload(hex("04 05 01 90 01 90 01 00 00 02 20 03 20 03 00 00 03 40 06 40 06 00 00 04 80 0c 80 0c 00 00 05 00 19 00 19 00")))   // header len 0x24 = 36 bytes; trailing "03 40 06 40" is stale buffer
}
@Test func reassemblesSleep() {
  var r = Reassembler(req: 0x32)
  _ = r.feed(hex("32 02 00 00 00 00 00 02 00 00 05 00 19 00 19 00 03 40 06 40"))
  #expect(r.feed(hex("2c 01 00 00 00 00 00 02 00 00 05 00 19 00 19 00 03 40 06 40")) == .payload([0x2C,0x01]))
}
@Test func failsOnErrorStatus() {
  var r = Reassembler(req: 0x33)
  #expect(r.feed(hex("33 00 00 00 00 00 00 05")) == .failed(.badParam))
}
```

  `hex(_:)` is a test helper that parses space-separated hex.

- [ ] **Step 2:** Run `swift test --filter FrameTests`.
  Expected: FAIL, because the symbols are undefined.

- [ ] **Step 3:** Implement `Frame.swift` with the interfaces above.

- [ ] **Step 4:** Run `swift test --filter FrameTests`.
  Expected: all 5 pass.

- [ ] **Step 5:** Commit: `feat(ble): request framing and notify reassembly`.

---

### Task 2: DPI table, MouseState, baseline and defaults

**Files:**
- Create: `Sources/RazerBLE/DPITable.swift`, `Sources/RazerBLE/MouseState.swift`, `docs/device-baseline.json`
- Test: `Tests/RazerBLETests/DPITableTests.swift`, `Tests/RazerBLETests/MouseStateTests.swift`

**Interfaces:**
- Produces:
  - `public struct DPIStage: Codable, Equatable, Sendable { public var id: UInt8; public var x: UInt16; public var y: UInt16 }`
  - `public struct DPITable: Codable, Equatable, Sendable { public var activeID: UInt8; public var stages: [DPIStage]; public var marker: UInt8; public var tailSlots: [DPIStage] }`
    - `stages` holds the first `count` entries.
    - `tailSlots` holds the preserved entries after `count`, up to 5 in total, taken from the raw read.
  - `public extension DPITable { static func parse(_ p: [UInt8]) throws -> DPITable; func encodeForWrite() -> [UInt8]; var activeIndex: Int }`
    - `encodeForWrite` produces the 38-byte write layout from spec/OpenSnek §6.2.1: always 5 entries (stages, then tail slots, padding missing ones by repeating the last stage with id `n+1`), the marker in byte 6 of entry 5, and a trailing `00`.
    - `activeIndex` resolves the active entry by matching id, then by 1-based index, then by clamping.
  - `public struct MouseState: Codable, Equatable, Sendable { public var dpi: DPITable; public var sleepSeconds: UInt16 }`
  - `public enum Defaults { public static let factory: MouseState; public static let baseline: MouseState }`
  - `public func validate(_ s: MouseState) throws`
    - Checks the limits in Global Constraints.
    - Throws `ValidationError` with a human-readable `message`.

- [ ] **Step 1: Write failing tests:**

```swift
// Captured 2026-11-06: 36 bytes (header len 0x24) — the final marker byte is NOT sent by this mouse.
let captured = hex("04 05 01 90 01 90 01 00 00 02 20 03 20 03 00 00 03 40 06 40 06 00 00 04 80 0c 80 0c 00 00 05 00 19 00 19 00")
@Test func parsesCapturedTable() throws {
  let t = try DPITable.parse(captured)
  #expect(t.stages.map(\.x) == [400,800,1600,3200,6400])
  #expect(t.stages.map(\.id) == [1,2,3,4,5])
  #expect(t.activeID == 4 && t.activeIndex == 3 && t.marker == 0)
}
@Test func roundTripsToWriteLayout() throws {
  let w = try DPITable.parse(captured).encodeForWrite()
  #expect(w.count == 38)
  #expect(Array(w[0..<36]) == captured)   // write layout == read bytes + marker(00) + trailing 00
  #expect(w[36] == 0 && w[37] == 0)
}
@Test func parsesFullLengthTableWithMarker() throws {   // OpenSnek devices send 37 bytes
  let t = try DPITable.parse(captured + [0x03])
  #expect(t.stages.count == 5 && t.marker == 3)
  #expect(try DPITable.parse(captured + [0x03]).encodeForWrite()[36] == 3)
}
@Test func parsesTruncatedTable() throws {   // short by a whole stage's tail: still OK if declared entries have id+x+y
  let t = try DPITable.parse(Array(captured.dropLast(2)))
  #expect(t.stages.count == 5 && t.stages[4].y == 6400)
}
@Test func activeResolutionFallbacks() throws {
  var t = try DPITable.parse(captured)
  t.activeID = 9;  #expect(t.activeIndex == 4)        // clamp
  t.stages = Array(t.stages.prefix(3)); t.activeID = 2; #expect(t.activeIndex == 1) // id match
}
@Test func rejectsOutOfRange() {
  var s = Defaults.factory; s.dpi.stages[0].x = 12050
  #expect(throws: ValidationError.self) { try validate(s) }
  s = Defaults.factory; s.sleepSeconds = 30
  #expect(throws: ValidationError.self) { try validate(s) }
}
@Test func factoryAndBaselineValues() {
  #expect(Defaults.factory.dpi.stages[Defaults.factory.dpi.activeIndex].x == 1600)
  #expect(Defaults.baseline.dpi.activeID == 4 && Defaults.baseline.sleepSeconds == 300)
}
@Test func baselineMatchesDocsFile() throws {
  let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    .appendingPathComponent("../../docs/device-baseline.json").standardized
  #expect(try JSONDecoder().decode(MouseState.self, from: Data(contentsOf: url)) == Defaults.baseline)
}
```

- [ ] **Step 2:** Run `swift test --filter "DPITableTests|MouseStateTests"`.
  Expected: FAIL.

- [ ] **Step 3:** Implement the code, and write `docs/device-baseline.json` by encoding `Defaults.baseline`.
  - `Defaults.baseline` must be exactly `DPITable.parse(captured)` with `sleepSeconds: 300`.
  - `Defaults.factory` is the same table with `activeID = 3`.

- [ ] **Step 4:** Run the same filter.
  Expected: all pass.

- [ ] **Step 5:** Commit: `feat(ble): DPI table codec, MouseState, defaults`.

---

### Task 3: BLE transport and read-only client; probe `read`

**Files:**
- Create: `Sources/RazerBLE/Transport.swift`, `Sources/RazerBLE/MouseClient.swift`, `Sources/proclick-probe/main.swift`
- Test: `Tests/RazerBLETests/MouseClientReadTests.swift`, `Tests/RazerBLETests/FakeTransport.swift`

**Interfaces:**
- Consumes: Task 1 and Task 2 types.
- Produces:
  - `public protocol VendorTransport: AnyObject, Sendable { func exchange(key: Key, payload: [UInt8]) async throws -> [UInt8]; var connectionState: AsyncStream<ConnectionState> { get } }`
  - `public enum ConnectionState: Equatable, Sendable { case searching, connected(name: String), disconnected }`
  - `public enum TransportError: Error, Equatable { case notConnected, timeout, status(Status), bluetoothUnavailable(String) }`
  - `public final class CoreBluetoothTransport: VendorTransport`
    - Lives on its own serial `DispatchQueue`.
    - Finds the mouse with `retrieveConnectedPeripherals(withServices:[vendorService])`, retrying every 3 s while not found.
    - Subscribes to notify `…1525`.
    - Serializes exchanges with an actor or queue. Each exchange gets a `Reassembler` and a 2 s timeout.
    - Battery percent comes from GATT `0x2A19` notifications. It is exposed as `var batteryPercent: AsyncStream<Int>`.
  - `public actor MouseClient { public init(transport: VendorTransport); public func readState() async throws -> MouseState; public func readBatteryRaw() async throws -> UInt8; public func readActiveDPI() async throws -> (x: UInt16, y: UInt16) }`
    - `readState` reads the DPI table, then the sleep value.
- `proclick-probe read` prints this, then exits 0:
  ```
  dpi: active=<id> stages=400,800,1600,3200,6400 marker=<m>
  sleep: <s>s
  battery: <raw>/255 (<pct>%)
  ```

- [ ] **Step 1: Write failing tests** with `FakeTransport`, a dictionary from `Key` to a canned payload or an error:
  - `readStateParsesFakeBytes`: the fake returns the captured DPI payload and `[0x2C,0x01]`, and `readState() == Defaults.baseline`.
  - `transportFailsPendingOnDisconnect`: the fake throws `.notConnected`, and `readState()` throws `TransportError.notConnected`.

- [ ] **Step 2:** Run `swift test --filter MouseClientReadTests`.
  Expected: FAIL.

- [ ] **Step 3:** Implement `Transport.swift`, `MouseClient.swift` and the probe's `read` subcommand, with manual argument parsing on `CommandLine.arguments`.

- [ ] **Step 4:** Run `swift test`.
  Expected: all tests pass.

- [ ] **Step 5 (hardware, read-only):** Run `swift run proclick-probe read`.
  Expected: `dpi: active=4 stages=400,800,1600,3200,6400 marker=0` and `sleep: 300s`. The battery value should roughly match the percentage shown in macOS Bluetooth settings.

  On first run, macOS asks for Bluetooth permission for Terminal. That is expected; grant it.

- [ ] **Step 6:** Commit: `feat(ble): CoreBluetooth transport, read client, probe read`.

---

### Task 4: Snapshots, verified writes, rollback, reset commands

**Files:**
- Create: `Sources/RazerBLE/SnapshotStore.swift`
- Modify: `Sources/RazerBLE/MouseClient.swift`, `Sources/proclick-probe/main.swift`
- Test: `Tests/RazerBLETests/MouseClientWriteTests.swift`, `Tests/RazerBLETests/SnapshotStoreTests.swift`

**Interfaces:**
- Produces:
  - `public struct SnapshotStore { public init(directory: URL); public func save(_ s: MouseState, reason: String) throws -> URL; public func latest() throws -> MouseState? }`
    - Files are named `yyyyMMdd-HHmmss-SSS-<reason>.json`.
    - Writes are atomic.
  - `public enum WriteOutcome: Equatable, Sendable { case applied(MouseState); case rolledBack(reason: String, restored: MouseState); case rollbackFailed(reason: String, snapshot: URL) }`
  - `MouseClient` additions:
    - `init(transport:snapshots:)`
    - `func apply(_ target: MouseState) async -> WriteOutcome`
    - `func restoreOriginal() async -> WriteOutcome`, which applies `Defaults.baseline`.
    - `func restoreFactory() async -> WriteOutcome`, which applies `Defaults.factory`.
  - The algorithm for `apply`:
    1. `validate(target)`. If it fails, return `.rolledBack(reason:, restored: current)` without writing anything.
    2. Read the current state.
    3. Save a snapshot.
    4. Write only the fields that changed: sleep through `sleepWrite` with u16 LE, the DPI table through `dpiTableWrite` with `encodeForWrite()`.
    5. Read the state back and compare it with the target.
    6. If it doesn't match, or anything threw, write the snapshot state back and read it back again.
       - If that restore matches, return `.rolledBack`.
       - Otherwise return `.rollbackFailed` with the snapshot path.
    - Stage ids and marker come from the current read, not from the target, so a UI edit cannot invent ids.
- `proclick-probe` subcommands:
  - `write-sleep <seconds>`
  - `write-dpi <active-index> <dpi,dpi,...>`
  - `restore-original`
  - `restore-factory`
  - `snapshots`, which lists the snapshot directory
  - Every write command prints the `WriteOutcome` and requires the `--yes` flag. Without it, it prints the planned bytes and exits 2.

- [ ] **Step 1: Write failing tests.** `FakeTransport` gains a mutable state, so writes change what later reads return. It also gains injectable faults.
  - `applyWritesOnlyChangedFields`: changing only sleep sends exactly one write, `sleepWrite` with payload `[0x58,0x02]` for 600 s.
  - `snapshotSavedBeforeWrite`: the fake records the order of events. The snapshot file exists when the first write arrives.
  - `mismatchRollsBack`: the fake stores sleep as 0 whatever is written. The result is `.rolledBack`, and the fake's final sleep is 300.
  - `writeTimesOutAndRollsBack`: the first write throws `.timeout`. The result is `.rolledBack`, and the state equals the original.
  - `rollbackFailureReportsSnapshot`: all writes throw. The result is `.rollbackFailed`, and the snapshot URL exists on disk.
  - `invalidTargetNeverWrites`: with DPI 50, no writes are recorded.
  - `restoreFactorySetsActive1600`: afterwards the fake's table resolves to active 1600 and sleep 300.
  - `SnapshotStoreTests.roundTrip`: save, then `latest()` returns the same state, in a temp directory.

- [ ] **Step 2:** Run `swift test --filter "MouseClientWriteTests|SnapshotStoreTests"`.
  Expected: FAIL.

- [ ] **Step 3:** Implement the code.

- [ ] **Step 4:** Run `swift test`.
  Expected: all pass.

- [ ] **Step 5:** Commit: `feat(ble): verified writes with snapshot rollback and reset commands`.

---

### Task 5: HARDWARE CHECKPOINT — first live writes (owner confirms each step)

No new code unless a step fails. Before each command, tell the owner what it
will change, and run it only after they confirm. After each one, also run
`swift run proclick-probe read` and record the output in
`docs/hid-capture.md` under "Write validation".

- [ ] **Step 1:** `swift run proclick-probe write-sleep 300 --yes`, writing the same value back.
  Expected: `applied`, and read shows `sleep: 300s`.
- [ ] **Step 2:** `write-sleep 600 --yes`.
  Expected: `applied` with `sleep: 600s`. Then `write-sleep 300 --yes`, and read shows 300.
- [ ] **Step 3:** `write-dpi 3 400,800,1600,3200,6400 --yes`, writing the same table back.
  Expected: `applied`. Read is unchanged, and moving the mouse feels unchanged.
- [ ] **Step 4:** `write-dpi 3 400,800,1600,2400,6400 --yes`.
  Expected: read shows stage 4 = 2400, and the cursor is noticeably slower. Then `restore-original --yes`.
  Expected: read is back at the baseline.
- [ ] **Step 5:** `restore-factory --yes`.
  Expected: active 1600. Then `restore-original --yes`.
  Expected: active 3200.

**If any step reports `rolledBack` or `rollbackFailed`:**
1. Stop.
2. Use the superpowers:systematic-debugging skill.
3. Tell the owner the outcome.
4. Don't continue to Task 12 until it's resolved.

If the mouse stops responding, follow the spec's fallbacks:
1. Run `restore-original`.
2. Turn the power slider off and on.
3. Re-pair the mouse.

- [ ] **Step 6:** Commit `docs/hid-capture.md` with `docs: record live write validation`.

---

### Task 6: HID capture of tilt and buttons; tune constants

**Files:**
- Modify: `Sources/proclick-probe/main.swift` (add `hid-capture`)
- Create: `Sources/InputEngine/DeviceTagger.swift` (IOHIDManager part only)
- Modify: `docs/hid-capture.md`

**Interfaces:**
- Produces:
  - `public final class DeviceTagger { public init(vendorID: Int = 0x1532, productID: Int = 0x009B); public var onValue: (@Sendable (HIDValue) -> Void)?; public func start() throws; public func lastPan(within: TimeInterval) -> Int?; public func lastButton(within: TimeInterval) -> (button: Int, down: Bool)? }`
  - `public struct HIDValue: Sendable { public let usagePage: Int; public let usage: Int; public let value: Int; public let timestamp: UInt64 }`
  - The IOHIDManager opens with `kIOHIDOptionsTypeNone`, never seizing the device, and matches on VID/PID.
- `proclick-probe hid-capture <seconds>` prints one line per value: `t=<ms> page=0x.. usage=0x.. value=..`.

- [ ] **Step 1:** Implement `DeviceTagger` (start and the callback) and the `hid-capture` subcommand.
- [ ] **Step 2 (hardware, owner participates):** Run `swift run proclick-probe hid-capture 30`. Ask the owner to:
  - (a) tilt left once quickly,
  - (b) tilt right once quickly,
  - (c) hold a tilt for 2 s,
  - (d) press each side button,
  - (e) press the bottom button, if there is one.

  Expected: AC Pan (page 0x0C, usage 0x238) values appear for tilts, and Button page (0x09) usages appear for the buttons. Terminal may need Input Monitoring permission; grant it if prompted.
- [ ] **Step 3:** Record in `docs/hid-capture.md`:
  - the pan sign for left and right,
  - the interval between repeats while held, and the first-repeat delay,
  - the button usage for each physical button.
- [ ] **Step 4:** Set `TiltDebouncer.silenceWindow` (Task 7). Use the larger of 250 ms and the first-repeat delay plus 50 ms. Write the chosen value and the reason in the doc.
- [ ] **Step 5:** Commit: `feat(input): HID device tagger and capture tool; document tilt pattern`.

---

### Task 7: Mapping model, tilt debouncer, router (pure)

**Files:**
- Create: `Sources/InputEngine/Mapping.swift`, `Sources/InputEngine/TiltDebouncer.swift`, `Sources/InputEngine/Router.swift`
- Test: `Tests/InputEngineTests/TiltDebouncerTests.swift`, `Tests/InputEngineTests/RouterTests.swift`, `Tests/InputEngineTests/MappingTests.swift`

**Interfaces:**
- Produces:
  - `public enum ButtonID: String, Codable, CaseIterable, Sendable { case left, right, wheel, tiltLeft, tiltRight, button4, button5 }`
  - `public enum Action: Codable, Equatable, Sendable`, with cases:
    - `passThrough`, `disabled`
    - `leftClick`, `rightClick`, `middleClick`
    - `back`, `forward`
    - `previousDesktop`, `nextDesktop`
    - `missionControl`, `appExpose`, `showDesktop`, `apps`
    - `shortcut(keyCode: UInt16, modifiers: UInt64)`
    - `dpiUp`, `dpiDown`, `dpiCycle`
    - `media(MediaKey)`, where `enum MediaKey: String, Codable { case playPause, next, previous, volumeUp, volumeDown, mute }`
  - `public struct MappingTable: Codable, Equatable, Sendable { public var actions: [ButtonID: Action]; public static let `default`: MappingTable; public func action(for: ButtonID) -> Action }`
    - The default maps tiltLeft to previousDesktop and tiltRight to nextDesktop. Every other button is passThrough.
  - `public struct TiltDebouncer { public static var silenceWindow: TimeInterval = 0.25; public mutating func handle(pan: Int, at: TimeInterval) -> TiltEvent? }`, where `enum TiltEvent { case left, right }`
    - The first non-zero pan after silence ≥ the window fires.
    - A pan in the same direction within the window is swallowed, and it extends the window.
    - A pan in the opposite direction fires immediately, as a new gesture.
  - `public enum RouteOutcome: Equatable { case pass, consume, consumeAndRun(Action) }`
  - `public func route(_ input: RoutedInput, tagged: Bool, table: MappingTable, debouncer: inout TiltDebouncer) -> RouteOutcome`, where `enum RoutedInput { case horizontalScroll(pan: Int, at: TimeInterval), button(ButtonID, down: Bool) }`
    - If `tagged` is false, the outcome is always `.pass`.
    - When a tilt action is `.passThrough`, horizontal scroll passes.
    - Otherwise every tagged horizontal scroll is consumed. The action runs only when the debouncer fires.
    - A button action runs on down and is consumed on both down and up. `.passThrough` passes.

- [ ] **Step 1: Write failing tests:**

```swift
@Test func oneTiltOneEvent() {
  var d = TiltDebouncer()
  #expect(d.handle(pan: -1, at: 0.00) == .left)
  for t in stride(from: 0.03, through: 2.0, by: 0.03) { #expect(d.handle(pan: -1, at: t) == nil) } // held 2 s
  #expect(d.handle(pan: -1, at: 2.40) == .left)   // new tilt after silence
}
@Test func reversalFiresImmediately() {
  var d = TiltDebouncer(); _ = d.handle(pan: 1, at: 0); #expect(d.handle(pan: -1, at: 0.05) == .left)
}
@Test func untaggedPanPassesThrough() {
  var d = TiltDebouncer()
  #expect(route(.horizontalScroll(pan: 3, at: 0), tagged: false, table: .default, debouncer: &d) == .pass)
}
@Test func taggedHeldTiltConsumedRunsOnce() {
  var d = TiltDebouncer()
  #expect(route(.horizontalScroll(pan: 1, at: 0), tagged: true, table: .default, debouncer: &d) == .consumeAndRun(.nextDesktop))
  #expect(route(.horizontalScroll(pan: 1, at: 0.1), tagged: true, table: .default, debouncer: &d) == .consume)
}
@Test func sideButtonsPassByDefault() {
  var d = TiltDebouncer()
  #expect(route(.button(.button4, down: true), tagged: true, table: .default, debouncer: &d) == .pass)
}
@Test func remappedButtonConsumedBothEdges() { /* table[.button5] = .missionControl → down: .consumeAndRun(.missionControl), up: .consume */ }
@Test func mappingCodableRoundTrip() { /* encode/decode a table containing .shortcut and .media */ }
```

  Use the pan signs recorded in Task 6. If left tilt turns out to be positive pan, flip the mapping in `TiltDebouncer` and keep the tests in terms of `.left`/`.right`.

- [ ] **Step 2:** Run `swift test --filter InputEngineTests`.
  Expected: FAIL.
- [ ] **Step 3:** Implement the code.
- [ ] **Step 4:** Run `swift test`.
  Expected: all pass.
- [ ] **Step 5:** Commit: `feat(input): mapping model, tilt debouncer, router`.

---

### Task 8: Desktop switching and action executor

**Files:**
- Create: `Sources/InputEngine/SpaceSwitcher.swift`, `Sources/InputEngine/ActionExecutor.swift`
- Modify: `Sources/proclick-probe/main.swift` (adds `space next|prev [--keys]`)

**Interfaces:**
- Produces:
  - `public enum SpaceMethod: String, Codable, Sendable { case dockSwipe, controlArrow }`
  - `public struct SpaceSwitcher { public var method: SpaceMethod; public func switchSpace(_ direction: TiltEvent) }`
    - **`.dockSwipe`:** post a synthetic Dock-swipe gesture sequence (began → changed → ended) through `CGEvent` with private gesture fields, so the system plays the real slide animation. Port the approach from Mac Mouse Fix's `TouchSimulator` `postDockSwipeEventWithDelta:type:phase:` (github.com/noah-nuebling/mac-mouse-fix, `Helper/Core/Touch/TouchSimulator.m`): event type 30 (dock control) paired with a type 29 gesture event, the swipe-type field set to horizontal, and phases began, then ended with an exit delta of ±1 desktop. Keep the magic field numbers in one commented block and cite the source.
    - **`.controlArrow`:** post Ctrl+Left (keycode 123) or Ctrl+Right (124) key down/up with `.maskControl`.
  - `public final class ActionExecutor { public init(spaces: SpaceSwitcher, dpi: (@Sendable (DPIStep) -> Void)?); public func run(_ a: Action) }`, where `enum DPIStep { case up, down, cycle }`
    - Mission Control: `open -b com.apple.exposelauncher`.
    - App Exposé: Ctrl+Down.
    - Show Desktop: F11 (keycode 103).
    - Apps: `open -b com.apple.apps.launcher` (verify the bundle id with `mdls` on the dev machine; fall back to `/System/Applications/Apps.app`).
    - Back / forward: post mouse buttons 4/5 (`otherMouseDown/Up`, buttonNumber 3/4).
    - Clicks: post synthetic mouse events at the cursor.
    - Shortcut: post key events.
    - Media keys: `NSEvent.otherEvent` systemDefined subtype 8 with the NX key codes.

- [ ] **Step 1:** Implement both files and the probe subcommand.
- [ ] **Step 2 (hardware/visual, owner watches):** Use at least 3 desktops. Run `swift run proclick-probe space next`, then `space prev`.
  Expected: one desktop move each way, with the swipe animation. Terminal needs Accessibility permission; grant it.
- [ ] **Step 3:** If nothing moves on macOS 26, use the fallback.
  1. Run `space next --keys`. Expected: it moves (requires System Settings › Keyboard › Keyboard Shortcuts › Mission Control › "Move right a space" to be enabled).
  2. Record in `docs/hid-capture.md` which method works.
  3. Set the default `SpaceMethod` to the method that works.
- [ ] **Step 4:** Commit: `feat(input): desktop switching and action executor`.

---

### Task 9: Event tap wiring — engine runs headless

**Files:**
- Create: `Sources/InputEngine/EventTap.swift`, `Sources/InputEngine/KarabinerCheck.swift`, `Sources/InputEngine/InputEngine.swift`
- Modify: `Sources/InputEngine/DeviceTagger.swift` (tag expiry), `Sources/proclick-probe/main.swift` (adds `run-engine`)
- Test: `Tests/InputEngineTests/EventTapLogicTests.swift`, `Tests/InputEngineTests/KarabinerCheckTests.swift`

**Interfaces:**
- Produces:
  - `public final class InputEngine { public init(tagger: DeviceTagger, executor: ActionExecutor); public var table: MappingTable; public func start() throws; public func stop(); public var isRunning: Bool }`
    - It installs a session-level `CGEventTap`, head-insert, default (active) mode, on `scrollWheel`, `otherMouseDown/Up`, `left/rightMouseDown/Up`.
    - Each event is classified into `RoutedInput`. Horizontal scroll is `scrollWheelEventDeltaAxis2 != 0` with `scrollWheelEventIsContinuous == 0`.
    - `tagged` is `tagger.lastPan(within: tagWindow) != nil` (or `lastButton`), with `tagWindow = 0.05` s.
    - The engine calls `route` and returns `nil` to consume.
    - Actions are dispatched asynchronously on the main queue, never inside the tap callback.
  - `func handleTapDisabled(type: CGEventType) -> Bool` returns true and re-enables the tap for `.tapDisabledByTimeout` and `.tapDisabledByUserInput`.
  - `DeviceTagger`: tags expire after `within`, using monotonic time (`mach_absolute_time`, converted).
  - `public enum KarabinerCheck { public static func grabsProClick(configURL: URL = default) -> Bool }`
    - It returns true when Karabiner is configured to grab this mouse: the device entry for vendor 5426 / product 155 is missing `"ignore": true`, or `ignore` is false.
    - It returns false when the config file is missing.

- [ ] **Step 1: Write failing tests:**
  - `reenablesOnDisableEvent`: `handleTapDisabled(.tapDisabledByTimeout)` returns true, using a fake tap handle.
  - `tagExpiresAfterWindow`: inject a pan at t=0. `lastPan(within: 0.05)` is non-nil at t=0.01 and nil at t=0.2. This needs an injectable clock: `DeviceTagger(clock: () -> TimeInterval)`.
  - `KarabinerCheckTests`:
    - the owner's current JSON, with `"ignore": true`, returns false;
    - the same JSON with `"ignore": false` returns true;
    - a missing file returns false.
- [ ] **Step 2:** Run `swift test --filter "EventTapLogicTests|KarabinerCheckTests"`.
  Expected: FAIL.
- [ ] **Step 3:** Implement the code. Add `proclick-probe run-engine`, which starts the engine with `.default` and runs until Ctrl+C.
- [ ] **Step 4:** Run `swift test`.
  Expected: all pass.
- [ ] **Step 5 (hardware, owner tests while `run-engine` is running):**
  - (a) Tilt right once → exactly one desktop to the right.
  - (b) Hold the tilt for 3 s → still exactly one desktop.
  - (c) Two-finger horizontal scroll on the trackpad in Safari → scrolls normally and switches no desktop.
  - (d) Side buttons in Safari → Back and Forward work.
  - (e) Vertical scroll on the mouse → normal.
  - Write the results in `docs/hid-capture.md`.
  - If (b) fails, raise `silenceWindow` and repeat.
  - If (c) fails, tighten `tagWindow`.
- [ ] **Step 6:** Commit: `feat(input): event tap engine with device tagging`.

---

### Task 10: App shell — signing, bundle, menu bar, permissions, launch at login

**Files:**
- Create: `scripts/setup-signing.sh`, `scripts/build-app.sh`, `Resources/Info.plist`, `Sources/AppCore/AppModel.swift`, `Sources/AppCore/Permissions.swift`, `Sources/ProClickMini/ProClickMiniApp.swift`, `Sources/ProClickMini/Views/MenuBarView.swift`
- Test: `Tests/AppCoreTests/PermissionsTests.swift`

**Interfaces:**
- Consumes: `MouseClient`, `CoreBluetoothTransport`, `InputEngine`, `KarabinerCheck`, `MappingTable`.
- Produces:
  - `@MainActor public final class AppModel: ObservableObject`. Published properties:
    - `connection: ConnectionState`
    - `batteryPercent: Int?`
    - `state: MouseState?`
    - `mapping: MappingTable`, persisted to `UserDefaults` key `mapping.v1` as JSON
    - `spaceMethod: SpaceMethod`, persisted under `spaceMethod`
    - `lastOutcome: WriteOutcome?`
    - `onboarding: OnboardingState`
    - `karabinerConflict: Bool`
  - AppModel methods:
    - `func refresh() async`, which re-reads the state on every `.connected`
    - `func apply(_ s: MouseState) async`
    - `func restoreOriginal() async`
    - `func restoreFactory() async`
    - `func setAction(_ a: Action, for b: ButtonID)`
    - `func setLaunchAtLogin(_ on: Bool) throws`, using `SMAppService.mainApp`
  - `public enum OnboardingState: Equatable { case ready, needsAccessibility, needsBluetooth, bluetoothOff }`
  - `public func onboardingState(accessibilityTrusted: Bool, bluetooth: CBManagerAuthorization, poweredOn: Bool) -> OnboardingState`
    - The checks run in priority order: Bluetooth denied, then Bluetooth off, then Accessibility missing.
    - When Accessibility is missing, the engine is not started. A 2 s timer polls `AXIsProcessTrusted()` and starts the engine as soon as it returns true.
- `setup-signing.sh` is idempotent.
  - If `security find-identity -v -p codesigning` already lists "ProClick Mini Dev", it does nothing.
  - Otherwise it uses `openssl` to create a self-signed certificate with extendedKeyUsage codeSigning and a 10-year validity.
  - It imports the certificate into the login keychain with `security import … -T /usr/bin/codesign`.
  - It sets trust for code signing with `security add-trusted-cert -p codeSign` (this prompts for the owner's password once).
- `build-app.sh`:
  1. Runs `swift build -c release --product ProClickMini`.
  2. Assembles `build/ProClick Mini.app` with `Contents/MacOS/ProClickMini` and `Info.plist`.
  3. Runs `codesign --force --options runtime --sign "<identity or ->" `.
  4. Prints the app path.
- The menu bar shows:
  - an icon (`computermouse`) with `NN%`
  - a status line: Connected, Disconnected or Searching
  - a DPI stage picker, which calls `apply` with the new activeID
  - "Open Settings…"
  - a "Launch at login" toggle
  - Quit
- The window scene `id: "settings"` has three tabs; they are placeholders until Tasks 11 and 12. It shows the onboarding banner when the state isn't `.ready`, and a Karabiner banner when `karabinerConflict` is true.

- [ ] **Step 1: Write failing tests** for `onboardingState`, covering every combination of the three inputs, including `onboardingStateWithoutAccessibility` → `.needsAccessibility`.
- [ ] **Step 2:** Run `swift test --filter PermissionsTests`.
  Expected: FAIL.
- [ ] **Step 3:** Implement everything listed above.
- [ ] **Step 4:** Run `swift test`.
  Expected: all pass.
- [ ] **Step 5:** Owner's one-time setup: run `bash scripts/setup-signing.sh`. It needs the owner's keychain password; ask them to run it with `!` if prompted.
  Expected: `security find-identity -v -p codesigning` lists "ProClick Mini Dev".
- [ ] **Step 6:** Run `bash scripts/build-app.sh && open "build/ProClick Mini.app"`.
  Expected:
  - The menu-bar icon shows the battery percentage.
  - The app asks for Bluetooth, and the onboarding banner asks for Accessibility.
  - After granting both, tilting switches desktops.
  - After rebuilding and relaunching, no new Accessibility prompt appears (this proves the stable signing works).
- [ ] **Step 7:** Commit: `feat(app): menu bar app shell, signing and permissions`.

---

### Task 11: Customize tab

**Files:**
- Create: `Sources/ProClickMini/Views/CustomizeTab.swift`, `Sources/ProClickMini/Views/MouseDiagram.swift`
- Modify: `Sources/AppCore/AppModel.swift` (any helpers)
- Test: `Tests/AppCoreTests/MappingPersistenceTests.swift`

**Interfaces:**
- Consumes: `AppModel.mapping`, `setAction`, `Action`, `ButtonID`.
- Produces:
  - **Diagram:** a top-down outline of the mouse drawn with SwiftUI `Path`, plus clickable hotspots for the 7 `ButtonID`s. The side buttons go on the left edge.
  - **Button list:** a list to the right, each row reading "Button → Action".
  - **Action picker:** clicking a button or row opens a popover with the action catalog grouped as Mouse, Navigation, Desktop, System, DPI, Media and Keyboard shortcut.
    - Choosing "Keyboard shortcut" opens a recorder that captures the next key-down with modifiers, using a local `NSEvent` monitor.
  - **Reset to defaults:** a button that restores `MappingTable.default`.
  - **Space method picker:** "Swipe animation" / "Keyboard (Ctrl+←/→)".

- [ ] **Step 1: Write failing tests:**
  - `mappingPersistsAcrossModels`: set an action, create a new `AppModel` with the same `UserDefaults(suiteName:)`, and the action is still there.
  - `corruptMappingFallsBackToDefault`: garbage under `mapping.v1` loads as `.default`.
- [ ] **Step 2:** Run `swift test --filter MappingPersistenceTests`.
  Expected: FAIL.
- [ ] **Step 3:** Implement the code. `AppModel` takes `UserDefaults` in `init` for testability.
- [ ] **Step 4:** Run `swift test`.
  Expected: all pass.
- [ ] **Step 5 (manual):**
  1. Build the app.
  2. Remap button 5 to Mission Control. Expected: pressing it opens Mission Control, and button 4 is still Back in Safari.
  3. Reset to defaults. Expected: button 5 is Forward again.
- [ ] **Step 6:** Commit: `feat(app): customize tab with remapping`.

---

### Task 12: Performance and Power tabs (only after Task 5 passed)

**Files:**
- Create: `Sources/ProClickMini/Views/PerformanceTab.swift`, `Sources/ProClickMini/Views/PowerTab.swift`
- Modify: `Sources/AppCore/AppModel.swift` (low-battery notification)
- Test: `Tests/AppCoreTests/LowBatteryTests.swift`

**Interfaces:**
- Consumes: `AppModel.state`, `apply`, `restoreOriginal`, `restoreFactory`, `lastOutcome`, `batteryPercent`.
- Produces:
  - **Performance tab:**
    - A list of 1–5 stages. Each stage has a stepper and slider (100–12000, step 50) and a radio button for the active stage.
    - Add and Remove stage buttons.
    - An Apply button that calls `apply`.
    - The tab shows `lastOutcome`:
      - `.applied`: green "Saved to mouse".
      - `.rolledBack`: orange text with the reason and "previous settings restored".
      - `.rollbackFailed`: red text with the snapshot path and the buttons "Restore my original settings" / "Restore factory defaults".
    - A note: "Polling rate can't be changed over Bluetooth."
  - **Power tab:**
    - Battery percentage and charge status.
    - A sleep-timer picker: 1, 2, 3, 5, 10, 15 min.
    - A low-battery notification toggle, on by default.
    - A "Reset mouse settings…" menu holding the two restore commands, each with a confirmation dialog.
  - `public struct LowBatteryNotifier { public mutating func update(percent: Int) -> Bool }`
    - It returns true (meaning: post a notification) the first time the percentage falls to 15 or below.
    - It resets once the percentage rises above 20.
    - Notifications are posted with `UNUserNotificationCenter`.

- [ ] **Step 1: Write failing tests:**
  - `notifiesOnceBelowThreshold`: inputs 22, 16, 15, 14, 10 produce true only at 15.
  - `rearmsAfterRecovery`: inputs 15, 25, 15 produce true twice.
- [ ] **Step 2:** Run `swift test --filter LowBatteryTests`.
  Expected: FAIL.
- [ ] **Step 3:** Implement the code.
- [ ] **Step 4:** Run `swift test`.
  Expected: all pass.
- [ ] **Step 5 (hardware, owner confirms each write):** In the app:
  1. Change the stage 4 DPI to 2400 and Apply. Expected: "Saved to mouse", and `proclick-probe read` agrees.
  2. Restore my original settings. Expected: back to the baseline.
  3. Set the sleep timer to 10 min, then back to 5 min. Expected: both show "Saved".
- [ ] **Step 6:** Commit: `feat(app): performance and power tabs with reset`.

---

### Task 13: Final verification

- [ ] **Step 1:** Run `swift test`. Expected: all pass, 0 failures.
- [ ] **Step 2:** Run `bash scripts/build-app.sh`. Expected: it signs with "ProClick Mini Dev", and `codesign -dv "build/ProClick Mini.app"` shows that authority.
- [ ] **Step 3 (owner):** Enable "Launch at login", log out and back in. Expected: the menu-bar icon appears.
- [ ] **Step 4:** Walk through the Review Focus list manually:
  1. Turn the mouse's power slider off. Expected: "Disconnected". Turn it back on. Expected: it reconnects within about 5 s and the battery returns.
  2. Trackpad horizontal scroll. Expected: works.
  3. Revoke Accessibility. Expected: banner appears and the app doesn't crash. Re-grant it. Expected: tilting works again without relaunching.
- [ ] **Step 5:** Commit any fixes. Then use superpowers:finishing-a-development-branch.
