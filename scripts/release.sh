#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT/Resources/Info.plist")}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
[[ "$DIST_DIR" = /* ]] || DIST_DIR="$PWD/$DIST_DIR"
export VERSION DIST_DIR
[[ $# -eq 0 || ( $# -eq 1 && "$1" == --check ) ]] || { echo "Usage: scripts/release.sh [--check]" >&2; exit 1; }
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "error: VERSION must have the form 1.0.0." >&2; exit 1; }
CHANNEL="${RELEASE_CHANNEL:-stable}"
case "$CHANNEL" in
  stable)
    [[ "${SIGNING_IDENTITY:-}" == "Developer ID Application:"* ]] || { echo "error: stable releases require SIGNING_IDENTITY='Developer ID Application: ...'. Use RELEASE_CHANNEL=preview only for an explicitly unnotarized preview." >&2; exit 1; }
    : "${NOTARY_PROFILE:?Stable releases require an existing NOTARY_PROFILE.}"
    IDENTITIES="$(security find-identity -v -p codesigning)"
    [[ "$IDENTITIES" == *\""$SIGNING_IDENTITY"\"* ]] || { echo "error: the selected Developer ID Application identity and private key are not available in this Mac's keychain." >&2; exit 1; }
    # Authenticate before an expensive build; this neither submits nor publishes software.
    xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" --output-format plist >/dev/null
    ;;
  preview) echo "Preparing an UNNOTARIZED preview. macOS may block first launch." ;;
  *) echo "error: RELEASE_CHANNEL must be stable or preview." >&2; exit 1 ;;
esac
if [[ "${1:-}" == --check ]]; then
  echo "Release preflight passed ($CHANNEL), version $VERSION, output $DIST_DIR. No build or submission performed."
  exit 0
fi
"$ROOT/scripts/build.sh"
if [[ "$CHANNEL" == stable ]]; then "$ROOT/scripts/notarize.sh"; fi
echo "Release files ready locally ($CHANNEL):"
cat "$DIST_DIR/AutoCorrect-$VERSION-universal.zip.sha256"
echo "Update Casks/autocorrect.rb with this final SHA-256 before publishing."
echo "This script does not create a GitHub release or upload files."
