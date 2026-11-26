#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/../.."
port="${1:-5461}"
if lsof -nP -iTCP:"$port" -sTCP:LISTEN >/dev/null 2>&1; then
  echo "Port $port is already in use; existing preview was left running." >&2
  exit 1
fi
flutter build web --no-pub -t design/mobile/main.dart --output build/mobile-preview
cp -R design/mobile/public/. build/mobile-preview/
python3 design/mobile/prepare_preview.py build/mobile-preview
exec python3 -m http.server "$port" --bind 127.0.0.1 --directory build/mobile-preview
