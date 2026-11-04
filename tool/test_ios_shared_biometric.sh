#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
artifact_dir="$(mktemp -d)"
trap 'rm -rf "$artifact_dir"' EXIT
source_file=ios/AutoFillBridge/Classes/SharedBiometricUnlock.swift
swiftc "$source_file" tool/tests/ios-shared-biometric/main.swift -o "$artifact_dir/tests"
"$artifact_dir/tests"
sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios14.0-simulator -sdk "$sdk" "$source_file"
