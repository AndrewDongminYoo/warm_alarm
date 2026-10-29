#!/usr/bin/env bash
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/.." && pwd)
package_root="${repo_root}/warm_alarm_macos/macos/warm_alarm_macos"
flutter_root=$(flutter --version --machine | python3 -c 'import json,sys; print(json.load(sys.stdin)["flutterRoot"])')
framework_directory="${flutter_root}/bin/cache/artifacts/engine/darwin-x64/FlutterMacOS.xcframework/macos-arm64_x86_64"
test -d "${framework_directory}/FlutterMacOS.framework"
swift build --package-path "${package_root}" --build-tests --jobs 2 \
	-Xswiftc -F"${framework_directory}" \
	-Xlinker -F -Xlinker "${framework_directory}" \
	-Xlinker -rpath -Xlinker "${framework_directory}"
bin_directory=$(swift build --package-path "${package_root}" --show-bin-path)
shopt -s nullglob
test_bundles=("${bin_directory}"/*.xctest)
if [[ ${#test_bundles[@]} -ne 1 ]]; then
	echo "Expected exactly one macOS XCTest bundle" >&2
	exit 1
fi

host_root=$(mktemp -d "${TMPDIR:-/tmp}/warm-alarm-native-tests.XXXXXX")
trap 'rm -rf "$host_root"' EXIT
app_root="${host_root}/WarmAlarmNativeTests.app/Contents"
mkdir -p "${app_root}/MacOS"
cat >"${app_root}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.andrew.warm-alarm.native-tests</string>
<key>CFBundleExecutable</key><string>WarmAlarmNativeTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
platform_developer=$(xcrun --sdk macosx --show-sdk-platform-path)/Developer
swiftc "${repo_root}/tool/macos_test_host.swift" \
	-F "${platform_developer}/Library/Frameworks" \
	-Xlinker -rpath -Xlinker "${platform_developer}/Library/Frameworks" \
	-Xlinker -rpath -Xlinker "${platform_developer}/usr/lib" \
	-Xlinker -rpath -Xlinker "${framework_directory}" \
	-o "${app_root}/MacOS/WarmAlarmNativeTests"
"${app_root}/MacOS/WarmAlarmNativeTests" "${test_bundles[0]}"
