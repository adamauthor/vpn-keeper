#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_path="${1:-$project_dir/dist/VPN Keeper.app}"
destination="${2:-$project_dir/dist}"
identifier=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist")
[[ "$identifier" == 'kz.local.VPNKeeper' ]] || { echo "Not a VPN Keeper bundle" >&2; exit 1; }
codesign --verify --strict "$app_path"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid bundle version" >&2; exit 1; }
architecture="$(uname -m)"
mkdir -p "$destination"
archive="$destination/VPN-Keeper-$version-$architecture.zip"
ditto --norsrc --noextattr -c -k --keepParent "$app_path" "$archive"
(cd "$destination" && shasum -a 256 "$(basename "$archive")" > "$(basename "$archive").sha256")
echo "Packaged: $archive"
