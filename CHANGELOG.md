# Changelog

Changes follow [Semantic Versioning](https://semver.org/).

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
