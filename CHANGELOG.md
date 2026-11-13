# Changelog

Changes follow [Semantic Versioning](https://semver.org/).

## [1.2.0] - 2026-11-13

### Added
- Work schedule (default 09:00–18:00, Mon–Fri, editable): inside the window the VPN is kept up without stopping;
  outside it VPN Keeper reconnects only after a manual connect, the desktop widget, or a `--connect` request, and then
  keeps the connection for a configurable number of hours.
- Desktop widget: connection status and a Connect / Disconnect button above the wallpaper, on every Space.
- `--connect [--hold-minutes N]` and `--disconnect` local commands (the app is started in the background if needed);
  `--runtime-status` now reports `connected`, `keepConnected`, `autoActive`, `inWindow`, `mode`, `schedule`, `holdUntil`.

### Fixed
- A network failure or a gateway-ended session ("Max time exceeded") no longer switches automatic reconnection off for
  good: retries continue with 30 / 60 / 120 / 300 second pauses until the tunnel is back. Only login failures stop
  retries, and a stale block from an older version is cleared on launch.
- Cisco service errors and a busy Cisco GUI are retried instead of blocking automation.
- A Cisco operation that hangs for more than three minutes is cancelled and the state is re-read.

## [1.1.3] - 2026-10-22

### Added
- Automatic selection of an enabled English keyboard layout when the password field receives focus.
- Repeat layout selection when returning to the app with the password field active.
- A visible hint if macOS cannot select an English input source.
- Public project documentation, MIT license, contribution templates, and macOS CI.

## [1.1.2] - 2026-10-22

### Fixed
- Treat Cisco GUI connection ownership as a distinct error rather than a network failure.
- Request a normal GUI quit and retry once when the tunnel is disconnected and the GUI blocks CLI connection control.
- Remove echoed credentials before parsing Cisco output, including split reads.
- Prevent background legacy Keychain access from waiting for an interactive authorization dialog.

### Added
- Safe local runtime status with connection stages and failure categories.

## [1.1.1] - 2026-10-22

### Added
- Google Authenticator migration payload version 2 support.
- Standard editing shortcuts and a local QR import command.

## [1.1.0] - 2026-10-22

### Added
- Local Google Authenticator export decoding and explicit account selection.

## [1.0.0] - 2026-10-22

### Added
- macOS menu bar application, Cisco CLI integration, and configurable authentication order.
- Local TOTP, Keychain storage, launch at login, and bounded reconnection attempts.
