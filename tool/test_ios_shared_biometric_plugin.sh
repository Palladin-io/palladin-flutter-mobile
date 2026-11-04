#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
artifact_dir="$(mktemp -d)"
trap 'rm -rf "$artifact_dir"' EXIT
primitive=ios/AutoFillBridge/Classes/SharedBiometricUnlock.swift
plugin=ios/AutoFillBridge/Classes/SharedBiometricUnlockPlugin.swift
source_fence=ios/AutoFillBridge/Classes/SharedMemberSourceFence.swift
swiftc "$primitive" "$plugin" tool/tests/ios-shared-biometric-plugin/main.swift -o "$artifact_dir/tests"
"$artifact_dir/tests"
if [[ ! -f "$source_fence" ]]; then
    echo "SharedMemberSourceFence.swift must be integrated in this checkout before SDK validation." >&2
    exit 1
fi
flutter_tool="$(command -v flutter)"
flutter_sdk="${FLUTTER_ROOT:-$(cd "$(dirname "$flutter_tool")/.." && pwd)}"
frameworks="$flutter_sdk/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64_x86_64-simulator"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios14.0-simulator \
    -sdk "$sdk" -F "$frameworks" "$primitive" "$source_fence" "$plugin"
