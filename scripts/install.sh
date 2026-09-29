#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SOURCE="$ROOT/dist/AutoCorrect.app"
REPLACE=0
OPEN=1
DESTINATION="/Applications"
[[ -w "$DESTINATION" ]] || DESTINATION="$HOME/Applications"
for OPTION in "$@"; do
  case "$OPTION" in
    --user) DESTINATION="$HOME/Applications" ;;
    --replace) REPLACE=1 ;;
    --no-open) OPEN=0 ;;
    --help|-h)
      echo "Usage: scripts/install.sh [--user] [--replace] [--no-open]"
      echo "Installs dist/AutoCorrect.app and opens it. Quit AutoCorrect before replacing it."
      exit 0 ;;
    *) echo "error: unknown option: $OPTION" >&2; exit 1 ;;
  esac
done
[[ "$(uname -s)" == "Darwin" ]] || { echo "error: installation requires macOS." >&2; exit 1; }
[[ -d "$SOURCE" ]] || { echo "error: run scripts/build.sh first." >&2; exit 1; }
if pgrep -x AutoCorrect >/dev/null; then
  echo "error: AutoCorrect is running. Quit it from its menu bar menu before installing." >&2
  exit 1
fi
mkdir -p "$DESTINATION"
TARGET="$DESTINATION/AutoCorrect.app"
if [[ -e "$TARGET" && "$REPLACE" != 1 ]]; then
  echo "error: $TARGET already exists. Use --replace to replace it after quitting." >&2
  exit 1
fi
STAGING="$(mktemp -d "$DESTINATION/.autocorrect-install-XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
# Do not copy FinderInfo attached by a synced source folder. Verify the copy
# before touching an existing installation. This is the locally built output.
ditto --noextattr "$SOURCE" "$STAGING/AutoCorrect.app"
xattr -cr "$STAGING/AutoCorrect.app"
codesign --verify --strict "$STAGING/AutoCorrect.app"
if [[ -e "$TARGET" ]]; then
  BACKUP="$DESTINATION/AutoCorrect.previous-$(date +%Y%m%d-%H%M%S).app"
  mv "$TARGET" "$BACKUP"
  echo "Previous app preserved at: $BACKUP"
fi
mv "$STAGING/AutoCorrect.app" "$TARGET"
echo "Installed: $TARGET"
if [[ "$OPEN" == 1 ]]; then
  open "$TARGET"
fi
