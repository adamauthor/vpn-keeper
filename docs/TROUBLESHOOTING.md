# Troubleshooting and local commands

## Keychain access after restart or update

Choose **Always Allow** for VPN Keeper in the system Keychain prompt. A one-time grant does not cover a new process. Normal restarts retain a persistent grant; rebuilding or changing the application's ad-hoc signature may require permission again.

If background reads fail, unlock macOS, open VPN Keeper, and click **Save / «Сохранить»** with an empty password field to preserve the saved password. In the system prompt, select **Always Allow** for this application. Never share your Mac password in an issue.

## Authentication failed

Automatic retries stop. Check the server, exact group, username, QR account, password keyboard layout, and system time. The default flow sends OTP to **Password** and the regular password to **Second Password**. Test the same account manually in Cisco if needed, then save corrected settings and click Connect.

Changing the layout does not transliterate an existing password or pasted text. Re-enter a password originally typed with the wrong layout.

## Cisco GUI owns connection control

When Cisco's graphical client prevents CLI connection control and the tunnel is disconnected, VPN Keeper can request a normal GUI quit and retry once. This setting is enabled by default. It never stops the VPN agent or force-quits the GUI. If it cannot release control, exit Cisco through its own Quit menu and try again.

## CLI or signature failure

The app looks for `/opt/cisco/secureclient/bin/vpn`, then `/opt/cisco/anyconnect/bin/vpn`. It checks Cisco's code signature before sending credentials. Obtain Cisco through your organization's approved installation channel. A failure reported inside a restricted development sandbox is not sufficient evidence of an invalid installation; confirm it in the normal user environment.

## Export images

Choose the page containing the VPN account. Google Authenticator multi-page exports are read page by page; accounts not present on the selected image are not imported. Unsupported algorithms, HOTP, malformed entries, and ambiguous source QR parameters are rejected.

## Schedule and desktop widget

Settings → **Расписание** sets the working window (default 09:00–18:00, Monday–Friday). Inside it the VPN is kept connected and recovers from any network failure or gateway-ended session. Outside it the app does not connect by itself; **Подключить**, the widget button or `--connect` bring the tunnel up and keep it for the configured hold time. The widget can be hidden from the menu bar menu.

## Local command interface

Commands never accept or print passwords, TOTP seeds, or current OTP values.

```bash
"/Applications/VPN Keeper.app/Contents/MacOS/VPNKeeper" --setup-status
"/Applications/VPN Keeper.app/Contents/MacOS/VPNKeeper" --runtime-status
"/Applications/VPN Keeper.app/Contents/MacOS/VPNKeeper" --inspect-qr /path/to/export.png
"/Applications/VPN Keeper.app/Contents/MacOS/VPNKeeper" --import-qr /path/to/export.png --account 0
```

- `--setup-status`: missing setup field names, auto-reconnect, login-item status, and automatic block state. Accesses the saved Keychain entry with prompts disabled.
- `--runtime-status`: last safe runtime snapshot without reading Keychain. Check `updatedAt`; a stopped application leaves a stale snapshot.
- `--inspect-qr`: account count and VPN candidate labels; for a single supported account, its display label and index. Labels can contain personal information; review them before sharing.
- `--import-qr`: stores exactly the selected TOTP account while preserving an existing password.
- `--set-server vpn.example.com`: fills an empty server, or validates the existing one; it refuses to replace a different stored server.
- `--set-identity --username alice --group Employees`: fills the username and group of an existing server profile.
- `--connect [--hold-minutes N]`: ask the running app (started in the background if needed) to connect now. Outside the work schedule the connection is kept for `N` minutes (15–1440, default from settings).
- `--disconnect`: disconnect the tunnel and switch automatic reconnection off.
- `--enable-login`: registers the application at its current location as a login item. Enable reconnection through the Connect button.

Do not paste raw Cisco logs or diagnostic bundles into public issues. A short failure category, app/Cisco version, and a redacted description are usually enough.
