#!/bin/zsh
# Renders every screen in light and dark into build/screenshots/.
set -euo pipefail
cd "${0:A:h}/.."
scripts/build-app.sh >/dev/null
rm -rf build/screenshots
"build/wamadu Dev.app/Contents/MacOS/Wamadu" --screenshots "$PWD/build/screenshots"
