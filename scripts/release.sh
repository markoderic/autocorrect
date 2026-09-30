#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${VERSION:-0.3.9}"
export VERSION
CHANNEL="${RELEASE_CHANNEL:-stable}"
case "$CHANNEL" in
  stable)
    [[ "${SIGNING_IDENTITY:-}" == "Developer ID Application:"* ]] || { echo "error: stable releases require SIGNING_IDENTITY='Developer ID Application: ...'. Use RELEASE_CHANNEL=preview only for an explicitly unnotarized preview." >&2; exit 1; }
    : "${NOTARY_PROFILE:?Stable releases require an existing NOTARY_PROFILE.}"
    ;;
  preview) echo "Preparing an UNNOTARIZED preview. macOS may block first launch." ;;
  *) echo "error: RELEASE_CHANNEL must be stable or preview." >&2; exit 1 ;;
esac
"$ROOT/scripts/build.sh"
if [[ "$CHANNEL" == stable ]]; then "$ROOT/scripts/notarize.sh"; fi
echo "Release files ready locally ($CHANNEL):"
cat "$ROOT/dist/AutoCorrect-$VERSION-universal.zip.sha256"
echo "Update Casks/autocorrect.rb with this final SHA-256 before publishing."
echo "This script does not create a GitHub release or upload files."
