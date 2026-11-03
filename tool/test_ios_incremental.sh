#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
artifact_dir="$(mktemp -d)"
trap 'rm -rf "$artifact_dir"' EXIT
sources=(
  ios/AutoFillBridge/Classes/AutoFillCacheStore.swift
  ios/AutoFillBridge/Classes/AutoFillCredentialPicker.swift
  ios/AutoFillBridge/Classes/AutoFillIncrementalCache.swift
  ios/AutoFillBridge/Classes/AutoFillIncrementalIdentities.swift
)
swiftc "${sources[@]}" tool/tests/ios-incremental/main.swift -o "$artifact_dir/tests"
"$artifact_dir/tests"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios14.0-simulator -sdk "$sdk" \
  "${sources[@]}" ios/AutoFillBridge/Classes/GeneratedPasswordHistory.swift \
  ios/AutoFillBridge/Classes/PendingPasswordSave.swift ios/CredentialProvider/CredentialProviderViewController.swift
flutter_executable="$(command -v flutter)"
flutter_root="$(cd "$(dirname "$flutter_executable")/.." && pwd)"
xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios14.0-simulator -sdk "$sdk" \
  -F "$flutter_root/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64_x86_64-simulator" \
  ios/AutoFillBridge/Classes/*.swift
