#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
artifact_dir="$(mktemp -d)"
trap 'rm -rf "$artifact_dir"' EXIT
swiftc ios/AutoFillBridge/Classes/PendingPasswordSave.swift \
  tool/tests/ios-save/main.swift -o "$artifact_dir/logic-tests"
"$artifact_dir/logic-tests"
simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
flutter_executable="$(command -v flutter)"
flutter_root="$(cd "$(dirname "$flutter_executable")/.." && pwd)"
# Import the resolved package's real public Objective-C API for SDK typechecking.
# No pod/app build or replacement runtime stub is needed for this check.
python3 - "$artifact_dir" <<'PYMODULE'
import json
from pathlib import Path
import sys
from urllib.parse import unquote, urljoin, urlparse

configuration = Path(".dart_tool/package_config.json").resolve()
packages = json.loads(configuration.read_text())["packages"]
package = next(item for item in packages if item["name"] == "sqflite_darwin")
root = Path(unquote(urlparse(urljoin(configuration.as_uri(), package["rootUri"])).path))
header = root / "darwin/sqflite_darwin/Sources/sqflite_darwin/include/sqflite_darwin/SqflitePluginPublic.h"
if not header.is_file():
    raise SystemExit("Resolved sqflite public SDK header is missing; run flutter pub get")
(Path(sys.argv[1]) / "module.modulemap").write_text(
    "module sqflite_darwin { header " + json.dumps(str(header)) + " export * }\n"
)
PYMODULE
xcrun --sdk iphonesimulator swiftc -typecheck -target arm64-apple-ios15.0-simulator \
  -sdk "$simulator_sdk" \
  -F "$flutter_root/bin/cache/artifacts/engine/ios/Flutter.xcframework/ios-arm64_x86_64-simulator" \
  -I "$artifact_dir" \
  ios/AutoFillBridge/Classes/*.swift ios/CredentialProvider/*.swift
xcrun --sdk iphonesimulator swiftc -target arm64-apple-ios26.2-simulator \
  -sdk "$simulator_sdk" ios/AutoFillBridge/Classes/PendingPasswordSave.swift \
  tool/tests/ios-save-sdk/main.swift -o "$artifact_dir/sdk-tests"
if [[ -n "${IOS_SAVE_TEST_SIMULATOR:-}" ]]; then
  xcrun simctl spawn "$IOS_SAVE_TEST_SIMULATOR" "$artifact_dir/sdk-tests"
fi
