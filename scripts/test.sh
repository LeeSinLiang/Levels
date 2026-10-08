#!/bin/zsh
set -euo pipefail
cd "${0:A:h}/.."
mkdir -p build/cache build/module-cache
CLANG_MODULE_CACHE_PATH="$PWD/build/module-cache" swift run --disable-sandbox --cache-path "$PWD/build/cache" MixerChecks
