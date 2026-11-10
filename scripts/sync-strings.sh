#!/bin/zsh
# Adds every localizable string the compiler finds in Sources/Maloche to the String Catalog and marks removed ones stale.
set -euo pipefail
cd "${0:A:h}/.."
# the compiler knows interpolation types (%@, %lld), a fresh build path re-emits every file and keeps the regular cache
rm -rf .build/strings
swift build --product Maloche --build-path .build/strings -Xswiftc -emit-localized-strings >/dev/null
xcrun xcstringstool sync Sources/Maloche/Resources/Localizable.xcstrings \
  --stringsdata .build/strings/**/Maloche.build/**/*.stringsdata
