#!/bin/sh
# dart-inga (C) 2026 Heiko Zimmermann
# SPDX-License-Identifier: BSD-3-Clause
#
# Builds the AMO package: exactly what Mozilla gets, nothing else. Run
# from the package root, after tool/build_firefox.sh:
#
#     tool/package_firefox.sh
#
# Writes dist/inga-firefox-<version>.zip (version read from the
# GENERATED manifest, which is the one that ships) and prints the
# archive listing.
#
# The counterpart of tool/package.sh for the Chrome store. It exists
# because the Firefox package used to be zipped by hand, which put it
# outside dist/ and made its shape depend on whoever ran the command.
set -eu

cd "$(dirname "$0")/.."
ext=build-firefox/ext

# The build must have run: without this guard an empty or stale tree
# would be packaged silently, and a missing directory would only show
# up as a confusing zip error.
if [ ! -f "$ext/manifest.json" ]; then
  echo "ABBRUCH: $ext/manifest.json fehlt -- zuerst tool/build_firefox.sh" >&2
  exit 9
fi

version=$(/usr/bin/python3 -c "import json; print(json.load(open('$ext/manifest.json'))['version'])")
out="dist/inga-firefox-$version.zip"

mkdir -p dist
rm -f "$out"
# COPYFILE_DISABLE and -X keep AppleDouble files and extended
# attributes out of the archive; both have reached a target host before.
(cd "$ext" && COPYFILE_DISABLE=1 zip -q -r -X "$OLDPWD/$out" .)
unzip -l "$out"
