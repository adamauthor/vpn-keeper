# Contributing

Focused fixes, synthetic CLI dialogue examples, documentation improvements, and compatibility reports are welcome.

## Development

1. Fork the repository and create a focused branch.
2. Install Xcode / Command Line Tools with Swift 6+.
3. Run `bash Scripts/test.sh` and `bash Scripts/build.sh`.
4. Describe the concrete problem, resulting behavior, and relevant validation in your pull request.

Use the existing naming and formatting conventions. Keep changes small enough to review. Update documentation when user-visible behavior changes and add meaningful regression coverage for parser, TOTP, or process-lifecycle fixes.

## Authentication fixtures

All examples must be synthetic: use `vpn.example.com`, `alice`, and invented group names. TOTP fixtures should use published RFC vectors or clearly synthetic seeds. Never use a real QR image, export payload, production password, internal VPN address, or customer identifier.

Preserve these boundaries:

- No raw credential values in arguments, files, diagnostics, test failures, or screenshots.
- No automatic certificate acceptance or allow-all-applications Keychain permissions.
- Unknown prompts stop the login flow; do not guess which secret a field expects.
- Keep retries bounded and cancellation prompt.
- Keep the GUI release behavior limited to normal Quit of a disconnected Cisco GUI.

## Community

Be respectful and precise. Discuss behavior and evidence, welcome different levels of experience, and avoid harassment or publishing personal information.

Contributions are accepted under this repository's [MIT license](LICENSE). For vulnerabilities, use [private reporting](SECURITY.md), not a public issue.
