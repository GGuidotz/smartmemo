#!/bin/zsh
# Compila "SmartMemo.app" (universale arm64 + x86_64, macOS 26+) con gli strumenti a riga di comando: niente progetto
# Xcode, come Nod e What's Going On.
#   ./build.sh              build/SmartMemo.app
#   ./build.sh --install    e la copia in /Applications (chiude la copia aperta) e la apre
#   ./build.sh --dmg        e crea dist/SmartMemo-<versione>.dmg
# Firma: con l'identità locale di Nod (~/.nod-signing) se c'è, altrimenti ad hoc. L'app non chiede permessi speciali:
# basta anche la firma ad hoc (il Terminale chiede l'Automazione solo per "Aggiorna nel Terminale").
set -euo pipefail
cd "${0:A:h}"

MODE=build
case "${1:-}" in
  --install) MODE=install ;;
  --dmg) MODE=dmg ;;
  "") ;;
  *) echo "uso: ./build.sh [--install|--dmg]" >&2; exit 64 ;;
esac

NAME="SmartMemo"
EXE=SmartMemo
VERSION=$(tr -d '[:space:]' < VERSION)
BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || echo 1)
COMMIT=$(git rev-parse --short HEAD 2>/dev/null || echo unknown)
BUILD=build
APP="$BUILD/$NAME.app"
PLIST="$APP/Contents/Info.plist"

grep -q "^## $VERSION " CHANGELOG.md || { echo "Manca la sezione '## $VERSION · <data>' in CHANGELOG.md" >&2; exit 1; }

# Traduzioni: ogni L("…") deve avere la sua voce in inglese (avviso, non blocca).
if command -v python3 >/dev/null; then
  python3 -I tools/check-strings.py >/dev/null || echo "Attenzione: traduzioni incomplete (python3 tools/check-strings.py)."
fi

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$PLIST"
/usr/bin/plutil -insert SMGitCommit -string "$COMMIT" "$PLIST"
# Il clone da cui si compila, per l'aggiornamento dai sorgenti (git pull && ./build.sh --install). Non nel DMG.
[ "$MODE" = dmg ] || /usr/bin/plutil -insert SMSourcePath -string "$PWD" "$PLIST"
cp -R Localization/*.lproj "$APP/Contents/Resources/"
cp CHANGELOG.md "$APP/Contents/Resources/CHANGELOG.md"   # Impostazioni › Aggiornamenti › Note di rilascio

# Apple Intelligence (FoundationModels): collegata "debole", così l'app parte anche dove il framework non c'è
# (Mac Intel). Se l'SDK non lo ha, il codice resta fuori da solo (#if canImport).
SDK=$(xcrun --sdk macosx --show-sdk-path 2>/dev/null || true)
LINK=()
if [ -n "$SDK" ] && [ -d "$SDK/System/Library/Frameworks/FoundationModels.framework" ]; then
  LINK=(-Xlinker -weak_framework -Xlinker FoundationModels)
fi

SOURCES=(Sources/**/*.swift)
for arch in arm64 x86_64; do
  mkdir -p "$BUILD/$arch"
  swiftc -O -swift-version 5 -parse-as-library -target "$arch-apple-macos26.0" "${LINK[@]}" "${SOURCES[@]}" -o "$BUILD/$arch/$EXE"
done
lipo -create "$BUILD/arm64/$EXE" "$BUILD/x86_64/$EXE" -output "$APP/Contents/MacOS/$EXE"

# Icona: Resources/Icon/AppIcon-1024.png (da tools/render-icon.py).
if [ -f Resources/Icon/AppIcon-1024.png ]; then
  ICONSET="$BUILD/AppIcon.iconset"
  rm -rf "$ICONSET"; mkdir -p "$ICONSET"
  for s in 16 32 128 256 512; do
    sips -z $s $s Resources/Icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s * 2)) $((s * 2)) Resources/Icon/AppIcon-1024.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
fi

plutil -lint "$PLIST" >/dev/null
xattr -cr "$APP"
KC="$HOME/.nod-signing/nod-signing.keychain"
if [ -f "$KC" ]; then
  SIGNING=local
  security unlock-keychain -p nod "$KC"
  codesign --force --keychain "$KC" --sign "Nod Local Signing" "$APP"
else
  SIGNING=adhoc
  codesign --force --sign - "$APP"
fi
codesign --verify --strict "$APP"
echo "Pronto: $APP ($VERSION, build $BUILD_NUMBER, commit $COMMIT, firma $SIGNING)"

case "$MODE" in
  install)
    /usr/bin/pkill -x "$EXE" 2>/dev/null || true
    rm -rf "/Applications/$NAME.app"
    cp -R "$APP" "/Applications/$NAME.app"
    touch "/Applications/$NAME.app"
    /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
      -f "/Applications/$NAME.app" 2>/dev/null || true
    open "/Applications/$NAME.app"
    echo "Installato in /Applications e aperto. Apertura rapida: ⌃⌥Spazio." ;;
  dmg)
    mkdir -p dist
    STAGE=$(mktemp -d)
    cp -R "$APP" "$STAGE/$NAME.app"
    ln -s /Applications "$STAGE/Applications"
    DMG="dist/SmartMemo-$VERSION.dmg"
    rm -f "$DMG"
    hdiutil create -quiet -volname "$NAME $VERSION" -srcfolder "$STAGE" -format UDZO "$DMG"
    rm -rf "$STAGE"
    shasum -a 256 "$DMG"
    echo "DMG: $DMG" ;;
esac
