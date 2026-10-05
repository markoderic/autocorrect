#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
VERSION="${VERSION:-0.3.11}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
# DIST_DIR lets a development build land somewhere other than dist/ so it cannot
# replace a recorded archive there (e.g. DIST_DIR="$PWD/dist/dev"). Default unchanged.
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
APP="$DIST_DIR/AutoCorrect.app"

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "error: AutoCorrect must be built on macOS with Xcode Command Line Tools." >&2
  exit 1
fi
for command in swift xcrun codesign ditto; do
  command -v "$command" >/dev/null || { echo "error: missing $command. Install Xcode Command Line Tools." >&2; exit 1; }
done
[[ -f Package.swift ]] || { echo "error: Package.swift is missing from $ROOT." >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: VERSION must have the form 0.3.7." >&2; exit 1; }

mkdir -p "$DIST_DIR"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/autocorrect-build.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT

for ARCH in arm64 x86_64; do
  TRIPLE="$ARCH-apple-macosx13.0"
  SCRATCH="$ROOT/.build/release-$ARCH"
  echo "Building ${ARCH}..."
  swift build --build-system native --configuration release --triple "$TRIPLE" --scratch-path "$SCRATCH" --product AutoCorrect
  BIN_DIR="$(swift build --build-system native --configuration release --triple "$TRIPLE" --scratch-path "$SCRATCH" --show-bin-path)"
  cp "$BIN_DIR/AutoCorrect" "$STAGING/AutoCorrect-$ARCH"
done

BUNDLE="$STAGING/AutoCorrect.app"
mkdir -p "$BUNDLE/Contents/MacOS" "$BUNDLE/Contents/Resources"
xcrun lipo -create "$STAGING/AutoCorrect-arm64" "$STAGING/AutoCorrect-x86_64" -output "$BUNDLE/Contents/MacOS/AutoCorrect"
xcrun strip -x "$BUNDLE/Contents/MacOS/AutoCorrect"
cp Resources/Info.plist "$BUNDLE/Contents/Info.plist"
cp THIRD_PARTY_NOTICES.md "$BUNDLE/Contents/Resources/THIRD_PARTY_NOTICES.md"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$BUNDLE/Contents/Info.plist"
if [[ -f Resources/AppIcon.icns ]]; then
  cp Resources/AppIcon.icns "$BUNDLE/Contents/Resources/AppIcon.icns"
fi
# Documents/iCloud can attach FinderInfo to newly generated bundles.
# Clear build-output metadata only so codesign can seal this local app.
xattr -cr "$BUNDLE"
if [[ "$SIGNING_IDENTITY" == "Developer ID Application:"* ]]; then
  codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$BUNDLE"
else
  codesign --force --sign "$SIGNING_IDENTITY" "$BUNDLE"
fi
codesign --verify --strict --verbose=2 "$BUNDLE"
for ARCH in arm64 x86_64; do
  xcrun lipo "$BUNDLE/Contents/MacOS/AutoCorrect" -verify_arch "$ARCH"
done

# Only replace this script's generated output after a complete successful build.
ZIP="$DIST_DIR/AutoCorrect-$VERSION-universal.zip"
# Archive outside synced Documents folders before moving the finished outputs.
ditto -c -k --sequesterRsrc --keepParent "$BUNDLE" "$STAGING/release.zip"
rm -rf "$APP"
mv "$BUNDLE" "$APP"
rm -f "$ZIP"
mv "$STAGING/release.zip" "$ZIP"
(
  cd "$DIST_DIR"
  shasum -a 256 "$(basename "$ZIP")" > "$(basename "$ZIP").sha256"
)
echo "Built: $APP"
echo "Archive: $ZIP"
echo "Signing identity: $SIGNING_IDENTITY"
echo "The release is not notarized unless you separately sign and notarize it."
