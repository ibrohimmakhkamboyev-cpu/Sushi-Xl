#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "[release-audit] $1" >&2
  exit 1
}

echo "[release-audit] Checking placeholder identifiers"
if rg -n "com\.example\.mobile|signingConfigs\.debug" mobile/android mobile/ios mobile/macos mobile/linux -g '!**/build/**'; then
  fail "Placeholder identifiers or debug release signing still exist."
fi

echo "[release-audit] Python compile"
python3 -m compileall backend/catalog_backend >/dev/null

echo "[release-audit] Admin panel JavaScript syntax"
find frontend/admin-panel -name '*.js' -print0 | xargs -0 -n1 node --check >/dev/null

echo "[release-audit] Flutter dependencies"
(
  cd mobile
  flutter pub get >/dev/null
  flutter analyze
  flutter test
)

echo "[release-audit] Completed successfully"
