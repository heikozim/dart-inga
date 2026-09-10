#!/bin/sh
# dart-inga (C) 2026 Heiko Zimmermann
# SPDX-License-Identifier: BSD-3-Clause
#
# Builds the Chrome Web Store package: exactly what the store gets,
# nothing else. Run from the package root, after tool/build.sh:
#
#     tool/package.sh
#
# Writes dist/inga-<version>.zip (version read from manifest.json) and
# prints the archive listing. The staging directory guarantees that no
# source file, override, git state or Finder metadata can slip in; -X
# keeps extended attributes out of the archive.
set -eu

version=$(/usr/bin/python3 -c "import json; print(json.load(open('manifest.json'))['version'])")
out="dist/inga-$version.zip"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT

mkdir -p "$staging/build" "$staging/icons" "$staging/inject" dist
cp manifest.json popup.html popup.css options.html options.css "$staging/"
# License texts travel with every binary distribution: Inga's own
# LICENSE plus the third-party notices for the code dart2js embeds.
cp LICENSE THIRD-PARTY-NOTICES "$staging/"
# The compiled files reference source maps that never ship; the bare
# reference makes the devtools report 404s (finding 2026-09-02), so the
# store build strips the sourceMappingURL line instead of merely
# leaving the .map files out.
for entry in background popup options; do
  grep -v '^//# sourceMappingURL=' "build/$entry.js" > "$staging/build/$entry.js"
done
cp icons/*.png "$staging/icons/"
cp inject/protocol.js "$staging/inject/"

rm -f "$out"
(cd "$staging" && zip -q -r -X "$OLDPWD/$out" .)
unzip -l "$out"
