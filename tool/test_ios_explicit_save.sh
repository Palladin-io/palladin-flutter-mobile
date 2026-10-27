#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
artifact_dir="$(mktemp -d)"
trap 'rm -rf "$artifact_dir"' EXIT
swiftc ios/AutoFillBridge/Classes/PendingPasswordSave.swift \
  tool/tests/ios-save/main.swift -o "$artifact_dir/logic-tests"
"$artifact_dir/logic-tests"
simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios15.0-simulator \
  -sdk "$simulator_sdk" \
  ios/AutoFillBridge/Classes/AutoFillCacheStore.swift \
  ios/AutoFillBridge/Classes/AutoFillCredentialPicker.swift \
  ios/AutoFillBridge/Classes/GeneratedPasswordHistory.swift \
  ios/AutoFillBridge/Classes/PendingPasswordSave.swift \
  ios/CredentialProvider/CredentialProviderViewController.swift
flutter_executable="$(command -v flutter)"
flutter_root="$(cd "$(dirname "$flutter_executable")/.." && pwd)"
xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios15.0-simulator \
  -sdk "$simulator_sdk" \
  -F "$flutter_root/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64_x86_64-simulator" \
  ios/AutoFillBridge/Classes/*.swift
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios26.2-simulator \
  -sdk "$simulator_sdk" ios/AutoFillBridge/Classes/PendingPasswordSave.swift \
  tool/tests/ios-save-sdk/main.swift -o "$artifact_dir/sdk-tests"
if [[ -n "${IOS_SAVE_TEST_SIMULATOR:-}" ]]; then
  xcrun simctl spawn "$IOS_SAVE_TEST_SIMULATOR" "$artifact_dir/sdk-tests"
fi
