#!/bin/bash
# Notarize an already Developer ID-signed build. Never strips quarantine or bypasses Gatekeeper.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT/dist/AutoCorrect.app"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to an existing notarytool keychain profile.}"
[[ -d "$APP" ]] || { echo "error: build AutoCorrect.app first." >&2; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: invalid bundle version." >&2; exit 1; }
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/autocorrect-notary.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
# Copy only our generated bundle outside synced folders, without Finder metadata.
# Never modify metadata on a downloaded customer app.
ditto --noextattr "$APP" "$STAGING/AutoCorrect.app"
xattr -cr "$STAGING/AutoCorrect.app"
codesign --verify --strict "$STAGING/AutoCorrect.app"
SIGNATURE="$(codesign -d --verbose=4 "$STAGING/AutoCorrect.app" 2>&1)"
[[ "$SIGNATURE" == *"Authority=Developer ID Application:"* ]] || { echo "error: notarization requires a Developer ID Application signature, not Apple Development or ad-hoc." >&2; exit 1; }
[[ "$SIGNATURE" == *"(runtime)"* && "$SIGNATURE" == *"Timestamp="* ]] || { echo "error: rebuild with hardened runtime and secure timestamp." >&2; exit 1; }
# Failed submission leaves the existing bundle/archive untouched.
ditto -c -k --sequesterRsrc --keepParent "$STAGING/AutoCorrect.app" "$STAGING/submission.zip"
# No passwords are placed in shell arguments or stored in the repository.
xcrun notarytool submit "$STAGING/submission.zip" --keychain-profile "$NOTARY_PROFILE" --wait --output-format plist > "$STAGING/result.plist"
mkdir -p "$ROOT/dist/notarization"
cp "$STAGING/result.plist" "$ROOT/dist/notarization/$VERSION.plist"
STATUS="$(/usr/libexec/PlistBuddy -c 'Print :status' "$STAGING/result.plist")"
[[ "$STATUS" == "Accepted" ]] || { echo "error: Apple returned $STATUS. See dist/notarization/$VERSION.plist; no release archive was replaced." >&2; exit 1; }
xcrun stapler staple "$STAGING/AutoCorrect.app"
xcrun stapler validate "$STAGING/AutoCorrect.app"
codesign --verify --strict "$STAGING/AutoCorrect.app"
spctl --assess --type execute --verbose=2 "$STAGING/AutoCorrect.app"
# Stapling changes the download. Rebuild the ZIP and checksum only after all checks pass.
ZIP="AutoCorrect-$VERSION-universal.zip"
ditto -c -k --sequesterRsrc --keepParent "$STAGING/AutoCorrect.app" "$STAGING/$ZIP"
(cd "$STAGING" && shasum -a 256 "$ZIP" > "$ZIP.sha256")
# Verify what customers will extract, not only the pre-archive bundle.
mkdir "$STAGING/extracted"
ditto -x -k "$STAGING/$ZIP" "$STAGING/extracted"
xcrun stapler validate "$STAGING/extracted/AutoCorrect.app"
spctl --assess --type execute --verbose=2 "$STAGING/extracted/AutoCorrect.app"
rm -rf "$APP"
mv "$STAGING/AutoCorrect.app" "$APP"
mv "$STAGING/$ZIP" "$ROOT/dist/$ZIP"
mv "$STAGING/$ZIP.sha256" "$ROOT/dist/$ZIP.sha256"
echo "Notarized and Gatekeeper-verified: $ROOT/dist/$ZIP"
