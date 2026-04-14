#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

usage() {
  cat <<'TXT'
Usage:
  scripts/release.sh <version>

Example:
  scripts/release.sh 0.2.0

What it does:
  - Builds a Release .app bundle into dist/
  - Zips the .app (preserving bundle metadata)
  - Computes SHA-256
  - Creates an annotated git tag v<version>
  - Pushes the tag to origin
  - Creates a GitHub Release and uploads the zip (requires `gh`)
TXT
}

if [[ ${1:-} == "-h" || ${1:-} == "--help" || -z ${1:-} ]]; then
  usage
  exit 0
fi

VERSION_RAW="$1"
VERSION="${VERSION_RAW#v}"
TAG="v${VERSION}"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "Not a git repository." >&2
  exit 1
fi

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Working tree is dirty. Commit or stash changes first." >&2
  git status --porcelain
  exit 1
fi

if git rev-parse "${TAG}" >/dev/null 2>&1; then
  echo "Tag ${TAG} already exists." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "Missing GitHub CLI 'gh'. Install it and run 'gh auth login'." >&2
  exit 1
fi

APP_NAME="NotePop"
DIST_DIR="$ROOT_DIR/dist"
APP_PATH="$DIST_DIR/$APP_NAME.app"
ZIP_NAME="$APP_NAME-$TAG-macOS.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"

echo "Building .app…"
bash scripts/build-app-bundle.sh

if [[ ! -d "$APP_PATH" ]]; then
  echo "Expected app at $APP_PATH but it was not found." >&2
  ls -la "$DIST_DIR" || true
  exit 1
fi

echo "Zipping…"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_PATH" "$ZIP_PATH"

SHA256=$(/usr/bin/shasum -a 256 "$ZIP_PATH" | awk '{print $1}')

echo "SHA-256: $SHA256"

echo "Tagging ${TAG}…"
git tag -a "${TAG}" -m "Release ${TAG}"

echo "Pushing tag…"
git push origin "${TAG}"

echo "Creating GitHub Release and uploading asset…"
TITLE="$APP_NAME ${TAG}"
NOTES=$(cat <<TXT
macOS build: $ZIP_NAME
SHA-256: $SHA256

Install:
- Download the zip
- Unzip
- Move $APP_NAME.app to /Applications (optional)
- Open (right click → Open the first time if Gatekeeper blocks it)
TXT
)

gh release create "${TAG}" "$ZIP_PATH" \
  --title "$TITLE" \
  --notes "$NOTES"

echo "Done."
