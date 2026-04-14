#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

APP_NAME="NotePop"
BUILD_DIR=".build/$(swift -print-target-info | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["target"]["triple"].split("-")[0] + "-apple-macosx")')/release"

# Build release binary
swift build -c release

BIN_PATH="$ROOT_DIR/.build/arm64-apple-macosx/release/$APP_NAME"
if [[ ! -f "$BIN_PATH" ]]; then
  # Fallback for other architectures/triples
  BIN_PATH="$(find "$ROOT_DIR/.build" -type f -path "*/release/$APP_NAME" | head -n 1)"
fi

if [[ -z "${BIN_PATH}" || ! -f "${BIN_PATH}" ]]; then
  echo "Could not find built binary '$APP_NAME'" >&2
  exit 1
fi

OUT_DIR="$ROOT_DIR/dist"
APP_DIR="$OUT_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$ROOT_DIR/App/Info.plist" "$CONTENTS_DIR/Info.plist"
cp "$BIN_PATH" "$MACOS_DIR/$APP_NAME"

chmod +x "$MACOS_DIR/$APP_NAME"

echo "Built: $APP_DIR"
