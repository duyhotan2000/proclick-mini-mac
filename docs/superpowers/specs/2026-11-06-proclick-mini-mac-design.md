# Pro Click Mini for macOS — Design

Date: 2026-11-06
Status: awaiting owner approval

## 1. Intent

Razer ships no macOS software for the Razer Pro Click Mini (RZ01-0399). The owner
wants a native macOS app that:

1. **Above all:** makes the scroll-wheel **tilt left / tilt right** switch to the
   previous / next desktop (Space). It should feel like a three-finger trackpad
   swipe, meaning the same slide animation.
2. Configures the mouse the way Razer Synapse does on Windows, within the limits
   of this hardware and the Bluetooth connection.

The owner is the only user. The mouse is connected over **Bluetooth**, not the
2.4 GHz dongle.

## 2. Goals

- One tilt moves exactly one desktop. Holding the tilt does nothing more, however
  many horizontal-scroll events the mouse repeats.
- Converting tilt into desktop switches applies **only to the Pro Click Mini**.
  The trackpad and any other mouse keep normal horizontal scrolling.
- The side buttons stay **Back / Forward** by default, everywhere.
- Every button can be remapped (7 inputs: left, right, wheel click, tilt left,
  tilt right, button 4, button 5).
- On-mouse settings over Bluetooth: DPI stages (count, values, active stage),
  sleep timer, battery level and charging status.
- A Synapse-style UI, chosen by the owner as layout "B":
  - **Menu-bar icon:** battery %, quick DPI stage picker, "Open Settings…", Quit.
  - **Settings window with three tabs:**
    - **Customize:** a mouse diagram. Click a button to choose its action.
    - **Performance:** edit the DPI stages and the active stage.
    - **Power:** battery level, sleep timer, low-battery notification.
- Launch at login and run quietly from the menu bar.

## 3. Non-goals

- Polling rate. It can't be set over Bluetooth, and the app only supports
  Bluetooth.
- 2.4 GHz dongle / USB support (VID 0x1532, PID 0x009A). Not now. Keep the
  transport behind a protocol so it could be added later.
- Lighting. The mouse has none.
- Scroll mode (free-spin vs tactile). It's a physical switch.
- Macros, per-app profiles, other Razer devices.
- App Store distribution or notarization.

## 4. Anti-goals (count as failure even if technically working)

- Holding a tilt flies across several desktops.
- Trackpad or other-mouse horizontal scrolling breaks or gets swallowed.
- A wrong write leaves the mouse misconfigured or unresponsive. Every write must
  use only verified key/payload shapes and must read back the result.
- Mouse input feels laggy or drops events because of the event tap.

## 5. Verified facts (probed on the owner's Mac, 2026-11-06)

| Item | Value |
|---|---|
| macOS | 26.7.1, Apple Silicon |
| Toolchain | Command Line Tools 26.6 with Swift 6.3.3. SwiftPM in it is **broken**: `swift-package` fails with a dyld `Symbol not found` against a mismatched `BuildServerProtocol.framework`. The owner (2026-11-07) chose to **install Xcode from the App Store** and build with Xcode's toolchain. |
| Bluetooth name / IDs | `ProClickM`, VID `0x1532`, PID `0x009B`, BLE |
| HID input report 1 | 6 buttons, AC Pan (8-bit), wheel (8-bit), X/Y (16-bit) |
| Other HID reports | 2 = consumer, 4/5 = undefined-usage 8-byte inputs, 6 = keyboard; max feature/output report size 1 (no vendor HID config channel) |
| GATT services | Device Information, Battery (`0x180F`), **Razer vendor `52401523-F97C-7F90-0E7F-6C6F4E36DB1C`** with characteristics `…1524` (write), `…1525` (notify), `…1526` (notify) |
| Access path | `CBCentralManager.retrieveConnectedPeripherals(withServices:[vendor])`, then connect, enable notify on `…1525`, write with response to `…1524`. Works while macOS HID owns the mouse. |

The protocol is OpenSnek's BLE vendor protocol (reference:
github.com/gh123man/OpenSnek `docs/protocol/BLE_PROTOCOL.md`). The request is
`[req, len, 00, 00, k0, k1, k2, k3] + payload`. The response is a notify header
`[req, len, 00 00 00 00 00, status]` (status `02` = OK), followed by payload
frames.

Reads confirmed on this mouse, all with status 02:

| Key | Meaning | Observed |
|---|---|---|
| `0B 84 01 00` | DPI stage table | `04 05 \| 01 9001 9001 00 00 \| 02 2003 2003 00 00 \| 03 4006 4006 00 00 \| 04 800C 800C 00 00 \| 05 0019 0019 00` (36 bytes per header len `0x24`; no marker byte) → active id 4, 5 stages 400/800/1600/3200/6400 |
| `0B 81 00 00` | active DPI | 3200 × 3200 |
| `0B 82 00 00` | active stage list | 400/800/1600/3200/6400 (no stage ids) |
| `05 84 00 00` | sleep timeout (u16 LE, seconds) | 300 |
| `05 81 00 01` | battery raw (0–255) | 56 (≈22%, matches GATT Battery Level 22) |
| `05 80 00 01` | battery/charge status | 01 |

**Untested on this model:** every write.
- `0B 04 01 00`: DPI stage table, 38-byte payload.
- `05 04 00 00`: sleep timeout.
- `08 04 01 <slot>`: on-mouse button bind.

Write payload shapes follow the OpenSnek spec §6.2.

## 6. Decisions

**Decided by the owner:**
- The tilt wheel switches desktops. The side buttons keep Back/Forward.
- One tilt equals one desktop. Holding adds nothing.
- UI layout B: menu-bar icon plus a Synapse-style settings window.
- Bluetooth is the connection.
- No other remap is required up front, but every button must be remappable.

- The builder may make test writes on the owner's mouse during development, as
  long as the mouse can always be reset (see "Write safety and recovery").
- A self-signed signing certificate may be added to the login keychain.

**Builder's calls (stated here so the owner can veto):**
- Swift 6 + SwiftUI, built with **Swift Package Manager** (from Xcode's
  toolchain; no `.xcodeproj` needed). A build script assembles the `.app` bundle: `Info.plist` with
  `LSUIElement`, `NSBluetoothAlwaysUsageDescription`, and ad-hoc `codesign`.
  - **Signing (approved by the owner):** a one-time setup script creates a
    self-signed code-signing certificate in the owner's login keychain, for
    example "ProClick Mini Dev". The build script signs with it, so
    Accessibility and Bluetooth permissions survive rebuilds. If the
    certificate is missing, the build falls back to ad-hoc signing.
- Minimum target: macOS 14.
- **Button remapping happens in the app, on the Mac,** not on the mouse:
  - A `CGEventTap` (needs Accessibility permission) catches events.
  - `IOHIDManager` matched to VID 0x1532 / PID 0x009B tells which device an
    event came from. The app sets a flag on raw HID values from the Pro Click
    Mini, and the event tap consumes only the matching events.
  - Remapping on the mouse (`08 04 …`) is out of scope for v1, because it is
    unverified and risky.
- **Side-button default (builder's call):** "Default" means pass-through. Buttons
  4/5 keep sending native mouse buttons 4/5, exactly as today; the owner asked
  for them to keep working as they do now. The first milestone therefore only
  intercepts tilt. Catching other buttons is needed only once the owner remaps
  one.
- **Other input tools:** Karabiner-Elements is installed and running.
  `~/.config/karabiner/karabiner.json` sets this mouse (VID 5426, PID 155) to
  `"ignore": true`, so Karabiner doesn't grab it and events keep the real
  device's identity. No Mac Mouse Fix, LinearMouse, BetterTouchTool or
  SteerMouse. The app should warn if a later Karabiner config starts grabbing
  this mouse (events would then come from Karabiner's virtual device).
- **Desktop switch method:**
  - **Primary:** post synthetic Dock-swipe gesture events, the technique used by
    Mac Mouse Fix. This gives the real swipe animation.
  - **Fallback:** if that fails on macOS 26, post Ctrl+← / Ctrl+→. These need
    "Move left/right a space" enabled in System Settings › Keyboard Shortcuts.
    Settings exposes a toggle for which method to use.
- **Tilt debounce:**
  - A tilt starts a "gesture" on the first non-zero pan value from this device
    and fires one switch.
  - Further pan events in the same direction are swallowed until pan input has
    been silent for about 250 ms, so holding fires nothing more.
  - The exact timing should be tuned against what the mouse actually sends
    (capture it first).
- **Action catalog for remapping:**
  - Default (pass-through), Disabled
  - Left / Right / Middle click
  - Back, Forward
  - Previous / Next desktop
  - Mission Control, App Exposé, Show Desktop, Apps (Launchpad was removed in
    macOS 26)
  - Keyboard shortcut (record a key combo)
  - DPI stage up / down / cycle
  - Media: play/pause, next, previous, volume up/down, mute
- **Persistence:** button mappings and app preferences go in `UserDefaults`
  (JSON-encoded). DPI and sleep live on the mouse; the UI reads them each time
  the mouse connects.
- **Write safety and recovery (owner's requirement):** there must always be a
  way to reset the mouse if anything unexpected happens. The official manual has
  **no hardware reset combination**. Its only factory reset is the Synapse
  (Windows) Settings › Reset tab. So the app provides recovery itself:
  - **Persistent snapshot:** before every write, the full readable state is
    saved to `~/Library/Application Support/<app>/snapshots/` as timestamped
    JSON. That state is the DPI table `0B 84 01 00` (raw bytes plus parsed
    values), active DPI `0B 81`, stage list `0B 82` and sleep `05 84`. The
    snapshot is written to disk before the write is sent.
  - **Baseline snapshot:** the state probed on 2026-11-06 goes in the repo
    (`docs/device-baseline.json`). It has active stage id 4 (3200), stages
    400/800/1600/3200/6400 with stage ids 1–5, no marker byte in the read
    (36-byte payload; written as `00`), and sleep 300 s.
  - **Write, verify, roll back:**
    - After each write, read it back and compare.
    - On a mismatch, an error status, or a timeout, write the pre-write
      snapshot back automatically, read it back again and report the result.
  - **Two reset commands**, each available in the app (Power tab › "Reset
    mouse settings…") and in the `probe` CLI, so recovery doesn't depend on
    the UI working:
    - "Restore my original settings" writes the baseline snapshot back.
    - "Restore factory defaults" writes the manual's defaults: stages
      400/800/1600/3200/6400, active 1600, sleep 300 s.
  - **Order of first live writes**, each confirmed with the owner before it
    is sent:
    1. Sleep timer `05 04`, writing back the current value, 300.
    2. Sleep timer set to a different value, then restored.
    3. DPI table `0B 04 01 00`, writing back the exact bytes just read.
    4. A changed DPI value, then restored.
    5. Test both reset commands.
    - Don't build the Performance or Power editing UI until steps 1–5 pass.
  - **Fallbacks if Bluetooth writes stop responding:**
    - Turn the power slider off and on.
    - Remove the mouse from macOS Bluetooth settings and pair it again.
    - Last resort: the Synapse Reset tab through the 2.4 GHz dongle on a
      Windows PC.
  - The UI enforces limits: DPI 100–12000 in steps of 50, 1–5 stages; sleep
    timer 1–15 min (to verify against firmware).
- **Battery:**
  - Prefer the standard GATT Battery Level (`0x180F`, notifiable).
  - Use vendor `05 81` as a cross-check.
  - Low-battery notification at ≤ 15% via `UserNotifications`.
- **Reconnects:** watch for the peripheral appearing and disappearing (sleep,
  power switch, the Bluetooth slot changing). Re-acquire it through
  `retrieveConnectedPeripherals`. The UI shows "Disconnected" when it can't.
- **Launch at login:** `SMAppService.mainApp`.
- **Location:** project root `/Users/duyho/StudySpace/razer_mouse`. It isn't a
  git repo yet; the builder may `git init`.

## 7. Architecture sketch (builder may refine)

- **`RazerBLE`** (library target)
  - CoreBluetooth transport: a serialized request queue and notify reassembly.
  - Typed commands: `readDPIStages`, `writeDPIStages`, `readSleep`,
    `writeSleep`, `readBattery`.
  - Pure framing/parsing code, unit-tested with the bytes captured above.
- **`InputEngine`**
  - IOHIDManager device tagging plus the CGEventTap.
  - The mapping table, the tilt debouncer and the action executor (key posts,
    Dock-swipe synth, media keys).
  - The debouncer and the mapping resolution are pure, unit-tested logic.
- **`App`** (SwiftUI)
  - `MenuBarExtra`, plus a `Settings`/`Window` scene with Customize /
    Performance / Power tabs.
  - Permission onboarding for Accessibility and Bluetooth.
- **`probe`** (CLI target)
  - Read and dump keys; guarded writes for development.
- **`scripts/build-app.sh`**
  - `swift build -c release`, assemble the `.app`, codesign.

## 8. Open for the builder

- The exact HID pattern of a held tilt, captured from this mouse, and the final
  debounce constants.
- Which of buttons 1–6 in HID report 1 correspond to which physical buttons.
  Expected: 1 L, 2 R, 3 middle, 4/5 side. The 6th is unknown and may be the
  bottom profile button or unused.
- Whether reports 4/5 carry useful passive status (DPI changes, battery).
- Whether the Dock-swipe synthesis still works on macOS 26.
- Visual design of the mouse diagram (simple drawn outline is fine).
