# Security architecture

VPN Keeper is a local controller for Cisco's VPN client. It has no app backend, telemetry, analytics SDK, or cloud account.

```mermaid
flowchart LR
    QR[Local QR image] --> Vision[Apple Vision / bounded decoder]
    Vision --> Vault[One selected TOTP account + password in Keychain]
    Vault --> TOTP[CryptoKit TOTP in memory]
    Vault --> CLI[Verified Cisco CLI]
    TOTP --> CLI
    CLI --> VPN[VPN gateway through Cisco]
```

## Storage

| Data | Location |
|---|---|
| Regular VPN password and one TOTP seed | Generic-password Keychain item, service `kz.local.VPNKeeper.credentials`, account `default-profile` |
| Server, group, username, authentication mode, preferences | App preferences, domain `kz.local.VPNKeeper` |
| Runtime status, timestamps, phase names, failure categories | App preferences; no credential values or raw Cisco transcript |
| Original QR image | Its original user-selected location; not copied or deleted |

The Keychain item uses `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` and disables synchronization. Legacy login-Keychain ACL authorization is also enforced. Background reads disallow interactive prompts. `Always Allow` applies to the trusted installed build; changing an ad-hoc signature may require reauthorization.

Storing the password and the TOTP seed together on one Mac reduces two-factor sign-in to access to that Mac. Read [Before you use it](../README.md#before-you-use-it) and confirm your organization allows it.

## Credential path

1. Decode the QR locally with Apple Vision.
2. Bound image size, protobuf size, field count, accounts, and text lengths.
3. Require explicit selection when an export includes account choices.
4. Generate TOTP with CryptoKit, immediately before it is sent. Wait for the next period when fewer than five seconds remain.
5. Validate Cisco's executable using Security.framework, including its identifier and Cisco signing team.
6. Pass group, username, and secrets over the child process's stdin, without a shell.
7. Strip expected credential echoes before response parsing. Discard the raw transcript on completion.

Cisco's TLS and VPN implementation performs network authentication and tunneling. The application does not accept untrusted certificates. Optional banner acceptance must be enabled deliberately after reading the banner.

## Failure boundaries

- Authentication and certificate failures, unsupported prompts, and unknown groups stop automatic retries.
- Network failures permit only three extra attempts, with backoff.
- Sleep, session changes, and loss of network pause attempts.
- GUI connection ownership can be released only by requesting a normal Cisco GUI quit when the tunnel is disconnected. The VPN service is not stopped or force-quit.
- The CLI exposes global tunnel state; the app does not prove which server owns an existing tunnel.
- This is not a kill switch and does not enforce network isolation.

## Threat model

This design reduces accidental disclosure in arguments, files, and diagnostics. It does not protect secrets from a malicious process with equivalent access to the unlocked account, a compromised operating system, a modified trusted Cisco binary, or a compromised VPN server. Password and TOTP on the same device reduce factor separation.

Use only an authorized VPN profile, a trustworthy Cisco installation, and an unlocked user session. Do not add support that bypasses certificate validation, broadens Keychain access to all applications, or exposes seeds in command output.

See [SECURITY.md](../SECURITY.md) for private reporting.
