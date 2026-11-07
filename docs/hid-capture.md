# Pro Click Mini — hardware findings (Bluetooth, macOS 26.7.1)

## Write validation (Task 5, 2026-11-07)

Every write is followed by `proclick-probe read`.

| Step | Command | Outcome | Read back |
|---|---|---|---|
| 1 (first try) | `write-sleep 300 --force --yes` | rollbackFailed: status 03 | unchanged (300 s, active 4) |
| — | **Cause:** header and payload were sent in one ATT write. The mouse needs the 8-byte header alone, then the payload in ≤20-byte chunks (OpenSnek §7.2). Fixed in `fe64250`. | | |
| 1 | `write-sleep 300 --force --yes` | applied | 300 s |
| 2 | `write-sleep 600 --yes` / `write-sleep 300 --yes` | applied / applied | 600 s / 300 s |
| 3 | `write-dpi 3 400,800,1600,3200,6400 --force --yes` | applied | unchanged |
| 4 | `write-dpi 3 400,800,1600,2400,6400 --yes` / `restore-original --yes` | applied / applied | stage 4 = 2400 / baseline |
| 5 | `restore-factory --yes` / `restore-original --yes` | applied / applied | active 3 (1600) / baseline |

Conclusion: the keys `05 04 00 00` (sleep) and `0B 04 01 00` (DPI table, 38-byte
payload) work on the Pro Click Mini over BLE. The mouse reads back 36 bytes; it
accepts the marker byte written as `00`.

## HID input capture (Task 6, 2026-11-07)

Captured with `proclick-probe hid-capture 120` while the owner tilted the wheel
and pressed each button.

| Physical input | HID usage | Values |
|---|---|---|
| Tilt left | Consumer `0x0C` / AC Pan `0x238` | `-1` repeated |
| Tilt right | Consumer `0x0C` / AC Pan `0x238` | `+1` repeated |
| Vertical wheel | Generic Desktop `0x01` / Wheel `0x38` | ±1 |
| Left / right click | Button `0x09` / 1, 2 | 1 down, 0 up |
| Wheel click | Button `0x09` / 3 | 1 down, 0 up |
| Back side button | Button `0x09` / 4 | 1 down, 0 up |
| Forward side button | Button `0x09` / 5 | 1 down, 0 up |
| Bottom button | — | no HID event (none exists, or it's the pairing button) |

### Tilt pattern

- **No first-repeat delay.** A tilt streams pan values every ~22 ms (≈45 Hz) from the very first report until it is released.
- **Bursts recorded:**
  - quick left: 202 ms, 11 values
  - quick right: 506 ms, 26 values
  - right held about 2 s: 1752 ms, 89 values
- **Biggest gap inside a burst:** 34 ms.
- **Zero values:** every movement report also carries AC Pan = 0, so pan **zeros must be ignored** when tagging and debouncing.

**Debounce constant:** `TiltDebouncer.silenceWindow = 0.25` s. The rule was
`max(250 ms, first-repeat delay + 50 ms)`; the first repeat comes about 22 ms
after the first report, so 250 ms wins. That is about 7× the largest gap inside
a burst, so a held tilt is never split into two switches. Two separate tilts
need at least 250 ms between them to count twice.

## Desktop switching (Task 8, 2026-11-07, macOS 26.7.1)

- `proclick-probe space next` / `space prev` with the synthetic Dock swipe moved exactly one
  desktop each way, with the native three-finger-swipe slide animation.
- First run went the wrong way: a **negative** origin offset moves to the desktop on the left.
  Fixed in `DockSwipe.swipe` (left = −1, right = +1).
- Default `SpaceMethod`: `.dockSwipe`. `.controlArrow` (Ctrl+←/→) stays as a fallback for a
  future macOS that ignores the CGEvent swipe fields.
