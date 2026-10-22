<p align="center">
  <img src="docs/assets/banner.svg" alt="VPN Keeper — your VPN, ready when you are" width="920">
</p>

<p align="center">
  <a href="https://github.com/adamauthor/vpn-keeper/actions/workflows/ci.yml"><img alt="CI" src="https://github.com/adamauthor/vpn-keeper/actions/workflows/ci.yml/badge.svg"></a>
  <img alt="macOS 13+" src="https://img.shields.io/badge/macOS-13%2B-182C38?logo=apple&logoColor=white">
  <img alt="Swift 6" src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&logoColor=white">
  <a href="LICENSE"><img alt="MIT license" src="https://img.shields.io/badge/license-MIT-14B8A6"></a>
</p>

<p align="center">
  A native menu bar companion for <strong>Cisco Secure Client / AnyConnect</strong>.<br>
  Start at login, generate your OTP locally, and reconnect when your VPN drops.
</p>

<p align="center"><strong>English</strong> · <a href="docs/README.ru.md">Русский</a> · <a href="https://github.com/adamauthor/vpn-keeper/releases">Releases</a> · <a href="docs/SECURITY-ARCHITECTURE.md">How secrets are handled</a></p>

## What it does

| | |
|---|---|
| **Reconnects automatically** | Checks Cisco every 15 seconds; network failures get three additional attempts, after 30, 60, and 120 seconds. |
| **Starts at login** | Uses the native macOS login-item service, after you sign in and unlock your Keychain. |
| **Generates OTP locally** | Reads a TOTP setup QR or a Google Authenticator export using Apple Vision and CryptoKit. |
| **Keeps secrets in Keychain** | Stores the VPN password and one selected TOTP account on this Mac, without iCloud synchronization. |
| **Handles your login order** | OTP → password, password → OTP, password + OTP, or OTP only. |
| **Helps prevent layout mistakes** | Selects an enabled English keyboard layout when you focus the password field. |

Cisco establishes the VPN tunnel. VPN Keeper controls the installed, signature-checked Cisco CLI. It is an independent community project, not affiliated with Cisco or Google.

## Get started

Requires **macOS 13+** and an installed Cisco Secure Client / AnyConnect with its VPN CLI. The application currently uses a Russian interface; this guide maps the main controls below.

1. [Download a release](https://github.com/adamauthor/vpn-keeper/releases), or [build from source](#build-from-source). Choose the archive for your Mac: `arm64` for Apple Silicon, `x86_64` for Intel.
2. Move **VPN Keeper.app** to **Applications** and open it.
3. Enter the VPN address, exact group name, username, and regular VPN password.
4. Choose your TOTP QR image with **«Выбрать QR…»**. For a Google Authenticator export, select the one account for your VPN.
5. Select the authentication order. The default is **Password = OTP; Second Password = regular password**.
6. Click **«Подключить»** to save and enable automatic reconnection. In the Keychain prompt, choose **Always Allow** for VPN Keeper.
7. Enable **«Запускать VPN Keeper после входа в macOS»** for launch at login. Approve the login item in System Settings if macOS requests it.

Close the window and leave the shield in the menu bar. **«Выключить авто»** pauses reconnection while preserving the current tunnel; **«Отключить VPN»** pauses reconnection and disconnects Cisco.

Release builds use **ad-hoc code signing**. They are not Apple Developer ID signed or notarized. Keep macOS protections enabled; see [building and signing](docs/BUILDING.md) if your deployment requires Developer ID distribution.

## Does Keychain ask on every restart?

**No.** Choose **Always Allow** for this installed build. Ordinary app restarts reuse that authorization. Choosing **Allow Once** only permits a single access. A locally rebuilt or re-signed application may need authorization again, and a locked Keychain must still be unlocked. [Apple explains the access options](https://support.apple.com/guide/keychain-access/if-youre-asked-for-access-to-your-keychain-kyca1243/mac).

If authorization is needed after an update, open VPN Keeper and click **«Сохранить»**. Leave the password field empty to retain the saved password, and choose **Always Allow** in the system dialog. Background connection attempts do not display Keychain prompts.

Keep the application in a permanent location. If you move it, disable and re-enable its login item so macOS remembers the new path.

## Local by design

- No analytics, account registration, QR conversion service, or app backend.
- QR images are decoded on-device and are not copied into the application.
- Importing an export saves **only the account you select**.
- Credentials go to Cisco through **stdin**, never shell interpolation, command arguments, or temporary files.
- Cisco's code signature is checked before it can receive credentials.
- Raw Cisco output, passwords, seeds, and OTP values are not written to the app's diagnostic log.
- Authentication failures, certificate errors, and unknown prompts stop automatic retries.

Storing the password and TOTP on the same unlocked Mac places both factors on that device. See the [security model and boundaries](docs/SECURITY-ARCHITECTURE.md) before deployment.

## Compatibility and boundaries

| Supported | Requires manual handling |
|---|---|
| Cisco Secure Client and legacy AnyConnect CLI paths | SAML/SSO and browser-based sign-in |
| Group / Username / Password / Second Password prompts | Push approvals and hardware tokens |
| TOTP SHA1, SHA256, SHA512; 6 or 8 digits; 10–120 second setup-QR periods | HOTP counter-based tokens |
| Google Authenticator exports, versions 1 and 2 | Unsupported or custom authentication prompts |
| One chosen account from multi-account or split exports | Connecting before macOS login or FileVault unlock |
| Graceful release of Cisco GUI connection control when the tunnel is disconnected | Certificate trust decisions and unread mandatory banners |

Google Authenticator migration exports do not include a custom period; imported TOTP accounts use 30 seconds. Each export page is read separately; select the page containing the account you need.

Cisco reports **global tunnel state**. An existing connection to another VPN is treated as connected; VPN Keeper does not verify or switch its server. Disconnect affects the current Cisco tunnel. This application is **not a kill switch**.

## Build from source

Install Xcode Command Line Tools with Swift 6+ and a suitable macOS SDK, then:

```bash
git clone https://github.com/adamauthor/vpn-keeper.git
cd vpn-keeper
bash Scripts/test.sh
bash Scripts/build.sh
```

The app is created at `dist/VPN Keeper.app`. There are **no third-party runtime dependencies**. [Build, signing, and release details →](docs/BUILDING.md)

Tests use synthetic data and RFC test vectors. They do not connect to a real VPN or access your Keychain. Coverage includes all 18 RFC 6238 vectors, actual QR recognition, bounded export decoding, prompt order, split credential echoes, retries, and process cancellation.

## Local diagnostics

```bash
"/Applications/VPN Keeper.app/Contents/MacOS/VPNKeeper" --setup-status
"/Applications/VPN Keeper.app/Contents/MacOS/VPNKeeper" --runtime-status
```

The first command reports missing setup fields and automatic/login settings. The second reports a safe snapshot of app state and connection stages, without opening Keychain. Check `updatedAt`: snapshots stop updating when the app exits.

[All local commands and troubleshooting →](docs/TROUBLESHOOTING.md)

## Contribute

See [CONTRIBUTING.md](CONTRIBUTING.md), [open an issue](https://github.com/adamauthor/vpn-keeper/issues/new/choose), or send a focused pull request. **Never attach a real QR export, password, OTP seed, or unredacted diagnostic bundle.** Report security issues privately using [SECURITY.md](SECURITY.md).

[MIT licensed](LICENSE). Cisco, AnyConnect, and Google Authenticator names belong to their respective owners.
