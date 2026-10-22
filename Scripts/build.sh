#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${VPNKEEPER_BUILD_DIR:-$project_dir/.build-local}"
app_path="${1:-$project_dir/dist/VPN Keeper.app}"
version="$(tr -d '\r\n' < "$project_dir/VERSION")"
[[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Invalid VERSION" >&2; exit 1; }
sign_identity="${VPNKEEPER_SIGN_IDENTITY:--}"
mkdir -p "$(dirname "$app_path")"
mkdir -p "$build_dir/module-cache" "$build_dir/cache" "$build_dir/config" "$build_dir/security"
export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/module-cache"

swift build --package-path "$project_dir" --disable-sandbox \
  --scratch-path "$build_dir/package" --cache-path "$build_dir/cache" \
  --config-path "$build_dir/config" --security-path "$build_dir/security" -c release
bin_dir="$(swift build --package-path "$project_dir" --disable-sandbox \
  --scratch-path "$build_dir/package" --cache-path "$build_dir/cache" \
  --config-path "$build_dir/config" --security-path "$build_dir/security" -c release --show-bin-path)"

# Build into a fresh sibling, then replace only our previous bundle.
staging="$build_dir/staging/VPN Keeper.app"
if [[ -e "$staging" ]]; then
  echo "Remove the previous staging directory first: $staging" >&2
  exit 1
fi
mkdir -p "$staging/Contents/MacOS" "$staging/Contents/Resources"
cp "$bin_dir/VPNKeeper" "$staging/Contents/MacOS/VPNKeeper"
cat > "$staging/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>VPNKeeper</string>
  <key>CFBundleIdentifier</key><string>kz.local.VPNKeeper</string>
  <key>CFBundleName</key><string>VPN Keeper</string>
  <key>CFBundleDisplayName</key><string>VPN Keeper</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$version</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>LSUIElement</key><true/>
  <key>LSMultipleInstancesProhibited</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>CFBundleIconFile</key><string>AppIcon</string>
</dict></plist>
PLIST
swift "$project_dir/Scripts/Icon.swift" "$build_dir/AppIcon.iconset"
cp "$build_dir/AppIcon.icns" "$staging/Contents/Resources/AppIcon.icns"
# Finder metadata on newly generated bundles can otherwise invalidate code signing.
xattr -dr com.apple.FinderInfo "$staging" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$staging" 2>/dev/null || true
if [[ "$sign_identity" == '-' ]]; then
  codesign --force --sign - "$staging"
else
  codesign --force --sign "$sign_identity" --options runtime --timestamp "$staging"
fi
codesign --verify --strict "$staging"
if [[ -e "$app_path" ]]; then
  previous_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$app_path/Contents/Info.plist" 2>/dev/null || true)
  if [[ "$previous_id" != 'kz.local.VPNKeeper' ]]; then
    echo "Refusing to replace an unrelated app: $app_path" >&2
    exit 1
  fi
  rm -rf "$app_path"
fi
mv "$staging" "$app_path"
xattr -dr com.apple.FinderInfo "$app_path" 2>/dev/null || true
xattr -dr com.apple.ResourceFork "$app_path" 2>/dev/null || true
codesign --verify --strict "$app_path"
echo "Built: $app_path"
