#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
"$ROOT/scripts/build.sh"
VERSION="${VERSION:-0.3.6}"
echo "Release files ready locally:"
cat "$ROOT/dist/AutoCorrect-$VERSION-universal.zip.sha256"
echo "Update Casks/autocorrect.rb with this SHA-256 before publishing."
echo "This script does not create a GitHub release or upload files."
