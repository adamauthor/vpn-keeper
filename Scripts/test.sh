#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="${VPNKEEPER_BUILD_DIR:-$project_dir/.build-local}"
mkdir -p "$build_dir/module-cache" "$build_dir/cache" "$build_dir/config" "$build_dir/security"
export CLANG_MODULE_CACHE_PATH="$build_dir/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_dir/module-cache"
test_command=(swift test --package-path "$project_dir" --disable-xctest --disable-sandbox
  --scratch-path "$build_dir/package" --cache-path "$build_dir/cache"
  --config-path "$build_dir/config" --security-path "$build_dir/security")
developer_dir="$(xcode-select -p)"
# Command Line Tools ship Swift Testing here, but SwiftPM may not add its search path.
testing_frameworks="$developer_dir/Library/Developer/Frameworks"
if [[ -d "$testing_frameworks/Testing.framework" ]]; then
  test_command+=(-Xswiftc -F -Xswiftc "$testing_frameworks" -Xlinker -F -Xlinker "$testing_frameworks" -Xlinker -rpath -Xlinker "$testing_frameworks")
  test_command+=(-Xlinker -rpath -Xlinker "$developer_dir/Library/Developer/usr/lib")
fi
"${test_command[@]}"
