#!/bin/sh
# dart-inga (C) 2026 Heiko Zimmermann
# SPDX-License-Identifier: BSD-3-Clause
#
# Builds the DERIVED Firefox variant into build-firefox/ext (gitignored;
# the one maintained source stays the Chrome form). Run from the
# package root:
#
#     tool/build_firefox.sh
#
# - compiles the three entry points with -Dfirefox=true, so the
#   compile-time flag selects the FirefoxBackend and dart2js
#   tree-shakes the Chrome binding (proven per build in docs/PROOFS.md)
# - copies the static files word for word
# - generates the Firefox manifest from manifest.json
#   (tool/firefox_manifest.dart -- background.scripts, gecko.id)
#
# Firefox loads build-firefox/ext temporarily (about:debugging, or
# webExtension.install over BiDi in the proof harness).
set -eu

out=build-firefox/ext
rm -rf "$out"
mkdir -p "$out/build" "$out/icons" "$out/inject"

for entry in background popup options; do
  dart compile js -Dfirefox=true -o "$out/build/$entry.js" "web/$entry.dart"
done

# Cut the package to the same shape as the Chrome one
# (tool/package.sh): dart2js leaves .map and .deps beside each
# output and writes a sourceMappingURL line into the .js. The maps
# never ship, the deps are build bookkeeping, and a bare reference
# makes the devtools report 404s -- so the line goes with them.
# Both flavors now carry exactly the three compiled files.
for entry in background popup options; do
  grep -v '^//# sourceMappingURL=' "$out/build/$entry.js" \
    > "$out/build/$entry.js.stripped"
  mv "$out/build/$entry.js.stripped" "$out/build/$entry.js"
  rm -f "$out/build/$entry.js.map" "$out/build/$entry.js.deps"
done

cp popup.html popup.css options.html options.css "$out/"
# License texts travel with every binary distribution; the one
# THIRD-PARTY-NOTICES covers both build flavors (the Firefox build
# tree-shakes chrome_extension out, the extra notice hurts nothing).
cp LICENSE THIRD-PARTY-NOTICES "$out/"
cp icons/*.png "$out/icons/"
cp inject/protocol.js "$out/inject/"

dart run tool/firefox_manifest.dart "$out/manifest.json"
echo "firefox-variante: $out"
