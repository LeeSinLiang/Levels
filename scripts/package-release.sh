#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."

mode=${1:---development}
if (( $# > 1 )) || [[ "$mode" != '--development' && "$mode" != '--release' ]]; then
    print -u2 'Usage: zsh scripts/package-release.sh [--development | --release]'
    exit 2
fi
if [[ "$mode" == '--release' ]]; then
    if [[ -z "${LEVELS_SIGNING_IDENTITY:-}" || "${LEVELS_SIGNING_IDENTITY:-}" == '-' || -z "${LEVELS_NOTARY_PROFILE:-}" ]]; then
        print -u2 'Release requires LEVELS_SIGNING_IDENTITY (Developer ID Application) and LEVELS_NOTARY_PROFILE (a notarytool Keychain profile). See docs/RELEASING.md.'
        exit 2
    fi
    # Certificate metadata only: never read or export its private key.
    if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fi -- "$LEVELS_SIGNING_IDENTITY" | /usr/bin/grep -q 'Developer ID Application:'; then
        print -u2 'The selected signing identity is not a valid Developer ID Application identity.'
        exit 2
    fi
    zsh scripts/build-app.sh
else
    LEVELS_SIGNING_IDENTITY=- zsh scripts/build-app.sh
fi

app="$PWD/build/Levels.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
mkdir -p dist build
staging=$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT

if [[ "$mode" == '--release' ]]; then
    /usr/bin/ditto -c -k --keepParent "$app" "$staging/Levels.zip"
    xcrun notarytool submit "$staging/Levels.zip" --keychain-profile "$LEVELS_NOTARY_PROFILE" --wait
    xcrun stapler staple "$app"
    xcrun stapler validate "$app"
    /usr/sbin/spctl --assess --type execute --verbose=2 "$app"
    filename="Levels-$version-universal.dmg"
else
    filename="Levels-$version-universal-test.dmg"
fi

payload="$staging/payload"
mkdir -p "$payload"
/usr/bin/ditto "$app" "$payload/Levels.app"
ln -s /Applications "$payload/Applications"
cp Resources/'Start Here.html' "$payload/Start Here.html"
if [[ "$mode" == '--development' ]]; then
    cat > "$payload/TEST BUILD.txt" <<'NOTICE'
Levels — test build

This app has a local development signature. Apple has not notarized it.
A downloaded copy may be blocked by Gatekeeper. The Start Here guide explains
Apple's per-app Open Anyway flow for a copy you trust. Do not disable Gatekeeper.

A public release requires a Developer ID Application certificate and Apple
notarization. No installer, audio driver, or terminal command is needed to use
Levels once macOS allows it to open.
NOTICE
fi

image="$staging/$filename"
/usr/bin/hdiutil create -volname Levels -srcfolder "$payload" -fs HFS+ -format UDZO "$image"
if [[ "$mode" == '--release' ]]; then
    /usr/bin/codesign --force --sign "$LEVELS_SIGNING_IDENTITY" --timestamp "$image"
    xcrun notarytool submit "$image" --keychain-profile "$LEVELS_NOTARY_PROFILE" --wait
    xcrun stapler staple "$image"
    xcrun stapler validate "$image"
fi
/usr/bin/hdiutil verify "$image"
mv -f "$image" "dist/$filename"
(
    cd dist
    /usr/bin/shasum -a 256 "$filename" > "$filename.sha256"
)
print "Packaged: $PWD/dist/$filename"
