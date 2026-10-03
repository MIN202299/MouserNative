#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Mouser"
BUNDLE_ID="com.duan.mouser"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA="$ROOT_DIR/.build/DerivedData"
APP_BUNDLE="$DERIVED_DATA/Build/Products/Debug/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
  -project "$ROOT_DIR/Mouser.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Debug \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGNING_ALLOWED=NO \
  build

SIGNING_IDENTITY="$(
  /usr/bin/security find-identity -v -p codesigning \
    | /usr/bin/sed -nE 's/.* ([0-9A-F]{40}) "Apple Development:.*/\1/p' \
    | /usr/bin/head -n 1
)"
if [[ -n "$SIGNING_IDENTITY" ]]; then
  codesign --force --deep --timestamp=none --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
fi

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
