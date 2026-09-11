#!/bin/sh
# dart-inga -- Inga, a Manifest V3 header inspector
# Copyright (C) 2026 Heiko Zimmermann
# SPDX-License-Identifier: BSD-3-Clause
#
# Builds the source archive AMO asks for whenever the submitted code is
# generated -- here by dart2js. Run from the package root, AFTER
# tool/build_firefox.sh, because the verification sums in the README are
# read off that very build:
#
#     tool/build_firefox.sh
#     tool/package_source.sh
#
# Writes dist/inga-<version>-source.zip and prints the listing.
#
# Two rules shape what goes in:
#
#   - Only what the BUILD reads. No tests, no docs, no changelogs, no
#     project readmes; they take no part in producing the output, and a
#     reviewer should not have to sift them.
#   - Everything comes out of `git archive <tag>`, never out of the
#     working tree. The tree can sit on a different state than the tag
#     without saying so, and an archive built from it would show a
#     reviewer something other than what was released. git archive reads
#     the object store, so it also cannot pick up macOS AppleDouble
#     files.
#
# The one deliberate exception is pubspec.lock: it is gitignored, so the
# worktree copy is the only one there is -- and it is the resolution the
# submitted build actually used.
set -eu
cd "$(dirname "$0")/.."

WEBEXT=${WEBEXT:-../dart-webext}

for tool in git zip sed shasum dart; do
    command -v "$tool" >/dev/null 2>&1 || {
        echo "ABORT: $tool is not on PATH -- nothing built." >&2
        exit 9
    }
done

# The version has one home, manifest.json, and is read from it. The
# pattern needs the opening quote of the VALUE, which is what keeps it
# off "manifest_version": 3.
version=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' manifest.json | head -1)
case $version in
    "" | *[!0-9.]*)
        echo "ABORT: no usable \"version\" in manifest.json (read: '$version')." >&2
        exit 9
        ;;
esac

tag="v$version"
git rev-parse -q --verify "$tag^{commit}" >/dev/null || {
    echo "ABORT: there is no tag $tag -- tag first, then build the source" >&2
    echo "       archive. It is meant to show the released state, not the" >&2
    echo "       working tree." >&2
    exit 9
}

# The pin has one home too: pubspec.yaml. Read here, never written.
webext_tag=$(sed -n 's/^ *ref: *\(v[0-9][0-9.]*\) *$/\1/p' pubspec.yaml | head -1)
[ -n "$webext_tag" ] || {
    echo "ABORT: no 'ref: vX.Y.Z' found in pubspec.yaml." >&2
    exit 9
}
git -C "$WEBEXT" rev-parse -q --verify "$webext_tag^{commit}" >/dev/null || {
    echo "ABORT: $WEBEXT does not know the pinned tag $webext_tag." >&2
    echo "       Point at another checkout with WEBEXT=<path>." >&2
    exit 9
}

ext=build-firefox/ext
[ -f "$ext/manifest.json" ] || {
    echo "ABORT: $ext is missing -- run tool/build_firefox.sh first." >&2
    echo "       The checksums in the README come out of that build." >&2
    exit 9
}
built=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$ext/manifest.json" | head -1)
[ "$built" = "$version" ] || {
    echo "ABORT: $ext carries version $built, the repository $version." >&2
    echo "       The build is stale; run tool/build_firefox.sh again." >&2
    exit 9
}

name="inga-$version-source"
out="dist/$name.zip"
staging=$(mktemp -d)
trap 'rm -rf "$staging"' EXIT
root="$staging/$name"
mkdir -p "$root/dart-inga" "$root/dart-webext" dist

git archive "$tag" \
    LICENSE THIRD-PARTY-NOTICES \
    manifest.json popup.html popup.css options.html options.css \
    analysis_options.yaml pubspec.yaml \
    icons inject lib tool web \
    | tar -x -C "$root/dart-inga"

git -C "$WEBEXT" archive "$webext_tag" \
    LICENSE pubspec.yaml analysis_options.yaml lib \
    | tar -x -C "$root/dart-webext"

cp pubspec.lock "$root/dart-inga/pubspec.lock"

# Generated, not copied: the local file points at the developer's
# neighbour checkout. In the archive dart-webext lies beside dart-inga
# under that same relative path, and the pin in pubspec.yaml stays
# untouched and visible.
cat > "$root/dart-inga/pubspec_overrides.yaml" <<'END'
# Redirects the webext dependency to the copy shipped in this archive,
# which holds exactly the tagged state pubspec.yaml pins. The build
# fetches nothing.
dependency_overrides:
  webext:
    path: ../dart-webext
END

# The sums go into the README through sed's `r`, because they are
# several lines; the single-line values go through `s`. Both would
# break on a `|`, a `&` or a backslash in a value, so the run stops
# instead of quietly writing something mangled.
sums="$staging/sums"
(cd "$ext" && shasum -a 256 build/*.js manifest.json | sed 's/^/    /') > "$sums"
sdk=$(dart --version 2>&1)
for value in "$version" "$tag" "$webext_tag" "$sdk"; do
    case $value in
        *'|'* | *'&'* | *'\'*)
            echo "ABORT: value contains a character this substitution" >&2
            echo "       cannot carry: '$value'" >&2
            exit 9
            ;;
    esac
done

readme="$root/README.md"
sed -e "s|@VERSION@|$version|g" \
    -e "s|@TAG@|$tag|g" \
    -e "s|@WEBEXT_TAG@|$webext_tag|g" \
    -e "s|@SDK@|$sdk|g" \
    -e "/@HASHES@/r $sums" \
    -e "/@HASHES@/d" \
    tool/source-readme.md.in > "$readme"
rm -f "$sums"

# Anywhere in the line, not just at its start: a placeholder left in the
# middle of a sentence is exactly the one that gets shipped unnoticed.
if grep -q '@[A-Z_][A-Z_]*@' "$readme"; then
    echo "ABORT: unreplaced placeholders in the README:" >&2
    grep -n '@[A-Z_][A-Z_]*@' "$readme" >&2
    exit 9
fi
# And the other direction: if the template ever loses @HASHES@, the sums
# would silently vanish from a README that still promises them.
grep -q '^    [0-9a-f]\{64\}  ' "$readme" || {
    echo "ABORT: no checksum lines in the README -- is @HASHES@ still" >&2
    echo "       in tool/source-readme.md.in?" >&2
    exit 9
}

rm -f "$out"
(cd "$staging" && zip -q -r -X "$OLDPWD/$out" "$name")
unzip -l "$out"
