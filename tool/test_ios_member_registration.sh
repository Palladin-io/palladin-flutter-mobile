#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
: "${FLUTTER_ROOT:?Set FLUTTER_ROOT to the Flutter SDK directory}"
artifact_dir="$(mktemp -d)"
trap 'rm -r "$artifact_dir"' EXIT
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
frameworks="$FLUTTER_ROOT/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64_x86_64-simulator"
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios14.0-simulator -sdk "$sdk" \
  -F "$frameworks" -framework Flutter ios/AutoFillBridge/Classes/*.swift \
  tool/tests/ios-member-registration/main.swift -o "$artifact_dir/tests"
SIMCTL_CHILD_DYLD_FRAMEWORK_PATH="$frameworks" xcrun simctl spawn "${IOS_SIMULATOR_ID:-booted}" "$artifact_dir/tests"
