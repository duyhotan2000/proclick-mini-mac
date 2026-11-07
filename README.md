# ProClick Mini for Mac

A small native macOS menu-bar app for the **Razer Pro Click Mini**, which has no Razer
software on macOS. Unofficial; not affiliated with or endorsed by Razer.

## What it does

- **Tilt the wheel left/right to switch desktops**, with the same slide animation as a
  three-finger trackpad swipe. One tilt = one desktop; holding does nothing extra.
- **Remap all 7 inputs** (left, right, wheel click, tilt left/right, two side buttons) to
  clicks, Back/Forward, desktop switching, Mission Control, App Exposé, Show Desktop,
  Apps, DPI up/down/cycle, media keys, or any keyboard shortcut.
- **DPI stages** (1–5 stages, 100–12000 DPI), **sleep timer**, **battery level** and a
  **low-battery notification**, all over Bluetooth.
- **Safe writes:** every change is backed up first, read back, and rolled back
  automatically if the mouse doesn't keep it. "Restore my original settings" and
  "Restore factory defaults" are always available.
- Works alongside the trackpad and other mice: only the Pro Click Mini's events are
  changed. Several Pro Click Minis can be connected; pick which one the settings apply to.

Requirements: macOS 14 or later, the mouse paired over **Bluetooth** (not the USB dongle).

## Install

1. Download `ProClickMini-<version>.dmg` from
   [Releases](https://github.com/duyhotan2000/proclick-mini-mac/releases).
2. Open it and drag **ProClick Mini** into **Applications**.
3. The app is self-signed, not notarized: the first time, macOS blocks it. Open
   **System Settings › Privacy & Security** and click **Open Anyway**.
4. Allow **Bluetooth**, **Accessibility** and **Input Monitoring** when asked.

## Build from source

Needs Xcode (Swift 6).

```sh
swift test                      # unit tests
bash scripts/setup-signing.sh   # once: self-signed "ProClick Mini Dev" certificate,
                                # so macOS keeps permissions across rebuilds
bash scripts/package.sh         # builds build/ProClick Mini.app and the .dmg
```

`swift run proclick-probe` is a command-line tool for reading the mouse, test writes
(dry run unless `--yes`), restoring settings and capturing raw HID input.

## How it works

- Settings use Razer's Bluetooth LE vendor service (protocol notes from
  [OpenSnek](https://github.com/gh123man/OpenSnek)); the device is verified by its PnP ID.
- Tilts and buttons are intercepted with a `CGEventTap`; an `IOHIDManager` listener tags
  which events came from the Pro Click Mini.
- The desktop-switch animation is a synthesized Dock swipe gesture, ported from
  [Mac Mouse Fix](https://github.com/noah-nuebling/mac-mouse-fix).

Design notes, the implementation plan and hardware findings are in `docs/`.

## License

MIT, see [LICENSE](LICENSE), except the Dock-swipe code derived from Mac Mouse Fix, which
stays under the MMF License. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
