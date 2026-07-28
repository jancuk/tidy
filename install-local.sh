#!/usr/bin/env bash
# Build and install Tidy from the current branch, replacing any existing copy.
# Run this on your Mac: bash install-local.sh
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SCHEME="Tidy"
PROJECT="$REPO_DIR/Tidy.xcodeproj"
APP_NAME="Tidy.app"
INSTALL_DIR="/Applications"
BUILD_DIR="$REPO_DIR/.build-output"

echo "==> Tidy — build & install"
echo "    Project : $PROJECT"
echo "    Branch  : $(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD)"
echo "    Commit  : $(git -C "$REPO_DIR" rev-parse --short HEAD)"
echo ""

# Require Xcode command-line tools
if ! command -v xcodebuild &>/dev/null; then
  echo "ERROR: xcodebuild not found. Install Xcode from the App Store first."
  exit 1
fi

# Quit the running app so the bundle can be replaced
if pgrep -x Tidy &>/dev/null; then
  echo "==> Quitting running Tidy…"
  osascript -e 'quit app "Tidy"' 2>/dev/null || killall Tidy 2>/dev/null || true
  sleep 1
fi

# Clean previous build artefacts
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

echo "==> Building (Release)…"
xcodebuild \
  -project "$PROJECT" \
  -scheme "$SCHEME" \
  -configuration Release \
  -derivedDataPath "$BUILD_DIR/DerivedData" \
  -archivePath "$BUILD_DIR/Tidy.xcarchive" \
  archive \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  AD_HOC_CODE_SIGNING_ALLOWED=YES \
  2>&1 | grep -E "^(error:|warning:|Build succeeded|FAILED|archive)" || true

# Verify archive was created
ARCHIVE="$BUILD_DIR/Tidy.xcarchive"
if [ ! -d "$ARCHIVE" ]; then
  echo ""
  echo "ERROR: Archive not found at $ARCHIVE"
  echo "       Run the full build log with: xcodebuild -project Tidy.xcodeproj -scheme Tidy -configuration Release archive 2>&1 | tail -40"
  exit 1
fi

echo "==> Archive created."

# Export the .app from the archive
APP_IN_ARCHIVE=$(find "$ARCHIVE/Products" -name "$APP_NAME" | head -1)
if [ -z "$APP_IN_ARCHIVE" ]; then
  echo "ERROR: $APP_NAME not found inside archive."
  exit 1
fi

# Remove old install, copy new one
echo "==> Installing to $INSTALL_DIR/$APP_NAME…"
if [ -d "$INSTALL_DIR/$APP_NAME" ]; then
  rm -rf "$INSTALL_DIR/$APP_NAME"
fi
cp -R "$APP_IN_ARCHIVE" "$INSTALL_DIR/$APP_NAME"

# Prefer a stable local Apple Development identity. A stable signature prevents
# macOS Keychain from treating every replacement build as a different app.
SIGNING_IDENTITY="$(
  security find-identity -v -p codesigning 2>/dev/null \
    | awk -F'"' '/Apple Development:|Developer ID Application:/ { print $2; exit }'
)"
if [ -n "$SIGNING_IDENTITY" ]; then
  echo "==> Signing with local Apple Development identity…"
  codesign \
    --force \
    --deep \
    --sign "$SIGNING_IDENTITY" \
    --entitlements "$REPO_DIR/Tidy/Tidy.entitlements" \
    "$INSTALL_DIR/$APP_NAME"
else
  echo "==> No Apple Development identity found; using an ad-hoc signature."
  codesign --force --deep --sign - "$INSTALL_DIR/$APP_NAME"
fi

# Clear quarantine so macOS doesn't block an ad-hoc signed build
xattr -dr com.apple.quarantine "$INSTALL_DIR/$APP_NAME" 2>/dev/null || true

# Launch
echo "==> Launching Tidy…"
open "$INSTALL_DIR/$APP_NAME"

echo ""
echo "✓ Done. Tidy is running from $INSTALL_DIR/$APP_NAME"
echo "  Build artefacts kept at: $BUILD_DIR"
