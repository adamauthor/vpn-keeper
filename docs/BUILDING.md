# Building and releasing

## Requirements

- macOS 13 or newer.
- Xcode or Command Line Tools with Swift 6+ for Swift Testing.
- A macOS SDK appropriate for the host OS.
- Cisco is needed for real VPN connections, not for the test suite.

No SwiftPM package dependencies are downloaded. Apple AppKit, SwiftUI, Vision, CryptoKit, Security, Network, ServiceManagement, and HIToolbox provide the runtime functionality.

## Build and test

```bash
bash Scripts/test.sh
bash Scripts/build.sh
```

Output: `dist/VPN Keeper.app`. A destination can be supplied as the first argument. `VPNKEEPER_BUILD_DIR` overrides the intermediate-build directory.

```bash
VPNKEEPER_BUILD_DIR=/tmp/vpn-keeper-build bash Scripts/build.sh "dist/VPN Keeper.app"
bash Scripts/package.sh "dist/VPN Keeper.app" dist
```

Builds target the host architecture. CI tests and packages Intel (`x86_64`) and Apple Silicon (`arm64`) separately. The app deployment target remains macOS 13.

## Code signing

The default `VPNKEEPER_SIGN_IDENTITY=-` creates an ad-hoc signature. This makes the local executable verifiable but is **not** Developer ID distribution or notarization. An ad-hoc rebuild changes identity and may need another `Always Allow` grant for the existing Keychain item.

For distribution with an identity you control:

```bash
VPNKEEPER_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"   bash Scripts/build.sh
```

The script uses hardened runtime and secure timestamping for a supplied signing identity. Notarization is a separate release step; it requires your own Apple developer credentials and is not configured in this repository. Do not disable Gatekeeper or add an allow-all-applications Keychain ACL as a workaround.

## CI

`.github/workflows/ci.yml` runs the tests and release build on both Mac architectures. Official GitHub Actions are pinned to commit SHAs. Pull-request jobs have read-only repository permissions and no signing credentials.

Test fixtures contain only synthetic accounts, public RFC 6238 vectors, and fake child processes. Tests never use the user's Keychain or connect to a real VPN. Vision/CoreImage image tests require an ordinary macOS environment; restricted automation sandboxes may prevent image rendering.

## Release

1. Update `VERSION` and the matching section of `CHANGELOG.md`.
2. Run tests and review the exact files being committed.
3. Push a tag matching the version, for example `v1.1.3`.
4. The tag workflow builds both architectures, verifies signatures, creates checksums, and publishes a GitHub release after the build jobs succeed.

Only the tag release job receives `contents: write`. Builds are still ad-hoc unless a separate, reviewed Developer ID signing process is configured. Release assets contain the app, not user preferences, Keychain data, QR images, or local logs.

The script-generated checksums detect damaged downloads; they do not replace Developer ID signing or notarization.
