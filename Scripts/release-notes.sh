#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
version="${1:?Usage: release-notes.sh VERSION}"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid version" >&2; exit 1; }
awk -v header="## [$version]" '
  index($0, header) == 1 { found = 1; next }
  found && /^## / { exit }
  found { print }
  END { if (!found) exit 1 }
' "$project_dir/CHANGELOG.md"
cat <<'NOTES'

### Install

Choose `arm64` for Apple Silicon or `x86_64` for Intel, extract the ZIP, and move **VPN Keeper.app** to Applications. macOS 13+ and Cisco Secure Client / AnyConnect are required.

These builds are ad-hoc signed, without Apple Developer ID or notarization. Keep macOS protections enabled. See the repository's building guide if you need Developer ID distribution.

Choose **Always Allow** in the Keychain prompt. Normal restarts reuse that grant; an ad-hoc rebuild may require it again.

All release assets are built in CI. They contain no user profiles, QR exports, passwords, or Keychain data. `.sha256` files provide download integrity checks.
NOTES
