#!/bin/bash
# Builds build/SimpleVectorizer.app; a release build is also installed into /Applications (INSTALL=0 to skip).
# Usage: Scripts/bundle.sh [debug|release]   (default: release)
# NOTARIZE=1 Scripts/bundle.sh   also has Apple notarize the app and staples the ticket (Developer ID, notarytool profile "notary")
set -euo pipefail
cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
VERSION="0.7.8"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"

if [ ! -f Resources/AppIcon.icns ]; then
    swift Scripts/make-icon.swift
fi

swift build -c "$CONFIG"
BIN="$(swift build -c "$CONFIG" --show-bin-path)"
APP="${APP:-build/SimpleVectorizer.app}"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/SimpleVectorizer" "$APP/Contents/MacOS/SimpleVectorizer"
cp "$BIN/simplevectorizer-mcp" "$APP/Contents/MacOS/simplevectorizer-mcp"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/SimpleVectorizer.sdef "$APP/Contents/Resources/SimpleVectorizer.sdef"
for LPROJ in Resources/*.lproj; do
    [ -d "$LPROJ" ] && cp -R "$LPROJ" "$APP/Contents/Resources/"
done

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>SimpleVectorizer</string>
    <key>CFBundleDisplayName</key><string>SimpleVectorizer</string>
    <key>CFBundleIdentifier</key><string>net.cieadrienm.simplevectorizer</string>
    <key>CFBundleExecutable</key><string>SimpleVectorizer</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>@VERSION@</string>
    <key>CFBundleVersion</key><string>@BUILD@</string>
    <key>CFBundleDevelopmentRegion</key><string>fr</string>
    <key>CFBundleLocalizations</key><array><string>fr</string><string>en</string></array>
    <key>LSMinimumSystemVersion</key><string>15.0</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSAppleScriptEnabled</key><true/>
    <key>OSAScriptingDefinition</key><string>SimpleVectorizer.sdef</string>
    <key>NSHumanReadableCopyright</key><string>cie Adrien M — Compagnie Adrien M</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.graphics-design</string>
    <key>NSLocalNetworkUsageDescription</key>
    <string>SimpleVectorizer écoute les commandes OSC locales (port UDP 9140) et expose une API HTTP locale (127.0.0.1:17940) pour le serveur MCP.</string>
    <key>CFBundleDocumentTypes</key>
    <array>
        <dict>
            <key>CFBundleTypeName</key><string>Image bitmap</string>
            <key>CFBundleTypeRole</key><string>Viewer</string>
            <key>LSHandlerRank</key><string>Alternate</string>
            <key>LSItemContentTypes</key>
            <array>
                <string>public.png</string>
                <string>public.jpeg</string>
                <string>public.tiff</string>
                <string>com.microsoft.bmp</string>
            </array>
        </dict>
    </array>
</dict>
</plist>
PLIST
sed -i '' -e "s/@VERSION@/$VERSION/" -e "s/@BUILD@/$BUILD/" "$APP/Contents/Info.plist"

if [ -z "${SIGN_IDENTITY:-}" ]; then
    IDENTITIES="$(security find-identity -v -p codesigning 2>/dev/null || true)"
    SIGN_IDENTITY="$(echo "$IDENTITIES" | sed -n 's/.*"\(Developer ID Application: [^"]*\)".*/\1/p' | head -1)"
    [ -n "$SIGN_IDENTITY" ] || SIGN_IDENTITY="$(echo "$IDENTITIES" | sed -n 's/.*"\(Apple Development: [^"]*\)".*/\1/p' | head -1)"
    [ -n "$SIGN_IDENTITY" ] || SIGN_IDENTITY="-"
fi
case "$SIGN_IDENTITY" in
    "Developer ID Application:"*) SIGN_FLAGS="--timestamp --options runtime" ;;
    *) SIGN_FLAGS="--timestamp=none" ;;
esac
if ! codesign --force $SIGN_FLAGS --sign "$SIGN_IDENTITY" "$APP/Contents/MacOS/simplevectorizer-mcp" "$APP" 2>/tmp/simplevectorizer-codesign.log; then
    echo "warning: signing with '$SIGN_IDENTITY' failed; falling back to ad hoc" >&2
    SIGN_IDENTITY="-"
    codesign --force --sign - "$APP/Contents/MacOS/simplevectorizer-mcp" "$APP"
fi
echo "signed: $SIGN_IDENTITY" >&2

if [ "${NOTARIZE:-0}" = "1" ]; then
    case "$SIGN_IDENTITY" in
        "Developer ID Application:"*) ;;
        *) echo "error: NOTARIZE=1 needs a Developer ID Application certificate" >&2; exit 1 ;;
    esac
    ditto -c -k --keepParent "$APP" "$APP.notarize.zip"
    xcrun notarytool submit "$APP.notarize.zip" --keychain-profile "${NOTARY_PROFILE:-notary}" --wait
    rm -f "$APP.notarize.zip"
    xcrun stapler staple "$APP"
    echo "notarized and stapled" >&2
fi

INSTALL_DIR="${INSTALL_DIR:-/Applications}"
if [ "${INSTALL:-$([ "$CONFIG" = release ] && echo 1 || echo 0)}" = 1 ]; then
    TARGET="$INSTALL_DIR/SimpleVectorizer.app"
    if pgrep -f "$TARGET/Contents/MacOS/SimpleVectorizer" >/dev/null; then
        echo "note: SimpleVectorizer is running from $TARGET — quit and reopen it to get this build" >&2
    fi
    rm -rf "$TARGET.new"
    ditto "$APP" "$TARGET.new"
    rm -rf "$TARGET"
    mv "$TARGET.new" "$TARGET"
    echo "installed: $TARGET" >&2
fi
echo "$APP"
