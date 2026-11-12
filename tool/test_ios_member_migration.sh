#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
artifact_dir="$(mktemp -d)"
trap 'rm -r "$artifact_dir"' EXIT
swiftc ios/AutoFillBridge/Classes/SharedMemberSourceFence.swift \
  ios/AutoFillBridge/Classes/SharedMemberSourceMigration.swift \
  tool/tests/ios-member-migration/main.swift -o "$artifact_dir/tests"
"$artifact_dir/tests"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios14.0-simulator -sdk "$sdk" \
  ios/AutoFillBridge/Classes/SharedMemberSourceFence.swift \
  ios/AutoFillBridge/Classes/SharedMemberSourceMigration.swift
