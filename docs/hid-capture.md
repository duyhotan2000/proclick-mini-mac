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
