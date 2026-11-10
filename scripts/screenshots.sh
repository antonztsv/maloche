#!/bin/zsh
# Renders every screen in light and dark into build/screenshots/, or with a language into build/screenshots-<language>/.
# Usage: scripts/screenshots.sh [language], e.g. de; the language applies to this run only.
set -euo pipefail
cd "${0:A:h}/.."
scripts/build-app.sh >/dev/null
CODE="${1:-}"
OUT="build/screenshots${CODE:+-$CODE}"
LANGUAGE_ARGS=()
if [[ -n "$CODE" ]]; then
  LANGUAGE_ARGS=(-AppleLanguages "($CODE)" -AppleLocale "$CODE")
fi
rm -rf "$OUT"
"build/maloche Dev.app/Contents/MacOS/Maloche" --screenshots "$PWD/$OUT" "${LANGUAGE_ARGS[@]}"
