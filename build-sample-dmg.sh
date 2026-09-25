#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "$0")" && pwd)"
output="$root/build"
user_temp="$(getconf DARWIN_USER_TEMP_DIR)"
derived_data="${user_temp%/}/TidySampleDerivedData"
app="${TIDY_SAMPLE_APP:-$derived_data/Build/Products/Release/Tidy.app}"

mkdir -p "$output"
if [[ -z "${TIDY_SAMPLE_APP:-}" ]]; then
  # Coverage embeds local source paths in the app binary.
  xcodebuild \
    -project "$root/Tidy.xcodeproj" \
    -scheme Tidy \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    ENABLE_CODE_COVERAGE=NO \
    build
fi

if [[ ! -x "$app/Contents/MacOS/Tidy" ]]; then
  echo "Release app was not found at $app" >&2
  exit 1
fi

architectures="$(lipo -archs "$app/Contents/MacOS/Tidy")"
host_arch="$(uname -m)"
if [[ " $architectures " != *" $host_arch "* ]]; then
  echo "Expected an app for $host_arch, found: $architectures" >&2
  exit 1
fi

staging="$(mktemp -d "$output/tidy-dmg.XXXXXX")"
trap 'rm -rf "$staging"' EXIT
ditto "$app" "$staging/Tidy.app"
xcrun strip -S -x "$staging/Tidy.app/Contents/MacOS/Tidy"
codesign --force --deep --sign - "$staging/Tidy.app"
codesign --verify --deep --strict "$staging/Tidy.app"
ln -s /Applications "$staging/Applications"

image="$output/Tidy-sample.dmg"
hdiutil create -quiet -volname 'Tidy Sample' -srcfolder "$staging" -ov -format UDZO "$image"
hdiutil verify -quiet "$image"
(
  cd "$output"
  shasum -a 256 Tidy-sample.dmg > Tidy-sample.dmg.sha256
)
echo "Sample DMG: $image"
echo "This local sample has no Developer ID signature or notarization."
