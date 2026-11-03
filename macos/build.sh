#!/bin/bash
# Build without installing; --install replaces the user's app and restarts it.
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -gt 1 || ( $# -eq 1 && "$1" != "--install" ) ]]; then
    echo "Usage: $0 [--install]" >&2
    exit 2
fi
if [[ "$(uname -s)" != Darwin ]]; then
    echo "The current Swift/AppKit implementation requires macOS 14+." >&2
    exit 1
fi

swift build -c release
BIN_DIR=$(swift build -c release --show-bin-path)
mkdir -p dist
STAGE=$(mktemp -d "$PWD/dist/.package.XXXXXX")
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/ClipKeep.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/ClipKeep" "$APP/Contents/MacOS/ClipKeep"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# Supply a stable certificate identity locally; never commit signing credentials.
SIGNING_IDENTITY="${CLIPKEEP_SIGNING_IDENTITY:--}"
codesign --force --sign "$SIGNING_IDENTITY" --identifier com.luojilab.clipkeep "$APP"
codesign --verify --deep --strict "$APP"
plutil -lint "$APP/Contents/Info.plist"
rm -rf dist/ClipKeep.app
mv "$APP" dist/ClipKeep.app
echo "Built dist/ClipKeep.app"

if [[ "${1:-}" == "--install" ]]; then
    DEST="$HOME/Applications/ClipKeep.app"
    mkdir -p "$HOME/Applications"
    INSTALL_STAGE=$(mktemp -d "$HOME/Applications/.clipkeep-install.XXXXXX")
    ditto dist/ClipKeep.app "$INSTALL_STAGE/ClipKeep.app"
    codesign --verify --deep --strict "$INSTALL_STAGE/ClipKeep.app"
    pkill -x ClipKeep || true
    if [[ -e "$DEST" ]]; then
        BACKUP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/clipkeep-backup.XXXXXX")
        mv "$DEST" "$BACKUP_DIR/ClipKeep.app"
        echo "Previous application saved in $BACKUP_DIR/ClipKeep.app"
    fi
    mv "$INSTALL_STAGE/ClipKeep.app" "$DEST"
    rmdir "$INSTALL_STAGE"
    open "$DEST"
    echo "Installed $DEST. An ad-hoc update may require accessibility re-authorization."
fi
