#!/bin/zsh
# Builds a compressed DMG for an app: the app, an Applications link, and the
# app's rounded icon as the volume icon (so the mounted disk and its window
# match the app icon instead of a generic square disk).
# Usage: zsh Scripts/make-dmg.sh <App.app> <volume name> <output.dmg>
set -euo pipefail
APP="$1"; VOLNAME="$2"; OUT="$3"
WORK="$(mktemp -d)"
STAGE="$WORK/stage"
mkdir -p "$STAGE"
ditto "$APP" "$STAGE/$(basename "$APP")"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "$VOLNAME" -srcfolder "$STAGE" -ov -format UDRW "$WORK/rw.dmg" >/dev/null
ICNS="$APP/Contents/Resources/TeachLens.icns"
if [[ -f "$ICNS" ]] && command -v SetFile >/dev/null; then
    MNT="$WORK/mnt"
    mkdir -p "$MNT"
    hdiutil attach "$WORK/rw.dmg" -mountpoint "$MNT" -nobrowse -quiet
    cp "$ICNS" "$MNT/.VolumeIcon.icns"
    SetFile -c icnC "$MNT/.VolumeIcon.icns" || true
    SetFile -a C "$MNT" || echo "::warning::Could not set the DMG volume icon"
    hdiutil detach "$MNT" -quiet
else
    echo "::warning::No TeachLens.icns or SetFile; DMG keeps the default disk icon"
fi
rm -f "$OUT"
hdiutil convert "$WORK/rw.dmg" -format UDZO -o "$OUT" >/dev/null
hdiutil verify "$OUT"
rm -rf "$WORK"
