#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/cache build/module-cache
# SwiftPM's native build system does not expose a multi-architecture option.
# The finished universal app needs no Swift or Xcode installation.
binaries=()
for architecture in arm64 x86_64; do
    triple="$architecture-apple-macosx14.2"
    build_flags=(--configuration release --product Levels --triple "$triple"
        --scratch-path "$PWD/build/$architecture" --disable-sandbox
        --cache-path "$PWD/build/cache")
    CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache" swift build "${build_flags[@]}"
    bin_path=$(swift build "${build_flags[@]}" --show-bin-path)
    binaries+=("$bin_path/Levels")
done

app="$PWD/build/Levels.app"
staging=$(mktemp -d "$PWD/build/app-stage.XXXXXX")
trap 'rm -rf -- "$staging"' EXIT
bundle="$staging/Levels.app"
mkdir -p "$bundle/Contents/MacOS" "$bundle/Contents/Resources"
/usr/bin/lipo -create "${binaries[@]}" -output "$bundle/Contents/MacOS/Levels"
cp Resources/Info.plist "$bundle/Contents/Info.plist"
cp Resources/AppIcon.icns Resources/'Start Here.html' "$bundle/Contents/Resources/"

# Keep the bundle identity so preferences survive the rename. A changed signer
# or rebuilt ad-hoc binary can still require renewed macOS audio consent.
identity=${LEVELS_SIGNING_IDENTITY:--}
signing_options=(--force --sign "$identity" --identifier local.soundmixer.app --options runtime)
if [[ "$identity" != '-' ]]; then
    signing_options+=(--timestamp --entitlements Resources/Levels.entitlements)
fi
/usr/bin/codesign "${signing_options[@]}" "$bundle"
/usr/bin/codesign --verify --deep --strict "$bundle"

# Move the previous bundle aside instead of overwriting a mapped executable.
if [[ -e "$app" ]]; then mv "$app" "$staging/previous.app"; fi
mv "$bundle" "$app"
print "Built universal app: $app"
if [[ "$identity" == '-' ]]; then
    print 'Development signature only; public distribution requires Developer ID and notarization.'
fi
