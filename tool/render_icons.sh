#!/bin/sh
# dart-inga -- Inga, a Manifest V3 header inspector
# Copyright (C) 2026 Heiko Zimmermann
# SPDX-License-Identifier: BSD-3-Clause
#
# Renders icons/*.png from icons/src/*.svg.
#
#     tool/render_icons.sh [zielverzeichnis]
#
# Default target is icons/; pass another directory to render somewhere
# else and compare before overwriting the shipped set.
#
# Which source serves which size is a decision, not an accident:
#
#     16, 32   inga-<state>-small.svg  -- toolbar. A full-bleed circle,
#              no legs, no antennae: at 16 px those strokes are half a
#              pixel and turn to haze, and the shell had to shrink to
#              make room for them.
#     48, 128  inga-<state>.svg        -- extension manager and store,
#              where the full drawing has the pixels to be read.
#
# The shipped icons/*.png were delivered as files on 2026-09-10, not
# produced by this script. Re-rendering from the same sources gives the
# same geometry (32 px: covered box 94% x 94%, ink 70% of the canvas,
# measured both ways) but not the same bytes -- a different rasteriser
# antialiases differently. So this script regenerates the icons, it does
# not reproduce those files byte for byte; do not use `cmp` against them
# as a check that the sources and the PNGs still agree.
#
# The renderer is a headless Chrome, because that is what this machine
# has: rsvg-convert, inkscape, ImageMagick, cairosvg and resvg are all
# absent (measured 2026-09-10). Any of them would do the same job; set
# CHROME to point elsewhere. --default-background-color=00000000 is what
# keeps the alpha channel -- without it every icon ships on white.
#
# The size is written INTO a copy of the source rather than left to
# --window-size alone: an SVG document renders at its own intrinsic
# width/height, so a 200x200 source in a 16x16 window yields a
# screenshot of its top left corner, which is empty. Measured
# 2026-09-10, and it looked exactly like a working run.
set -eu
cd "$(dirname "$0")/.."

out=${1:-icons}
CHROME=${CHROME:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}

# PIT-054: a renderer that is not there must abort, not produce nothing
# and let the caller read the absence as a result. Exit 9 says "did not
# run", which is neither success nor a bad icon.
if [ ! -x "$CHROME" ]; then
    echo "ABBRUCH: kein Renderer unter \"$CHROME\" -- nichts gerendert." >&2
    echo "         Anderen Browser ueber CHROME=<pfad> angeben." >&2
    exit 9
fi

# Scratch space under the gitignored build/, not $TMPDIR: it keeps the
# sized copies next to the sources and the trap below removes them.
work=build/icons-tmp
rm -rf "$work"
mkdir -p "$work"
trap 'rm -rf "$work"' EXIT INT TERM

mkdir -p "$out"
for state in neutral orange red; do
    for size in 16 32 48 128; do
        case $size in
            16|32) src=icons/src/inga-$state-small.svg ;;
            *)     src=icons/src/inga-$state.svg ;;
        esac
        [ -r "$src" ] || { echo "ABBRUCH: $src fehlt." >&2; exit 9; }

        sized=$work/inga-$state-$size.svg
        sed "s/width=\"[0-9]*\" height=\"[0-9]*\"/width=\"$size\" height=\"$size\"/" \
            "$src" > "$sized"
        grep -q "width=\"$size\" height=\"$size\"" "$sized" || {
            echo "ABBRUCH: Groesse in $src nicht ersetzt -- nichts gerendert." >&2
            exit 9
        }

        # No --user-data-dir. Measured 2026-09-10, one variable at a
        # time: with the flag this Chrome never returns -- not from the
        # repo, not from /private/tmp, not from $TMPDIR, with a fresh
        # directory each time or a shared one. Without it three
        # consecutive runs took three to four seconds each and twelve in
        # a row went through. The hang looks exactly like a slow render,
        # which is why it is written down here rather than rediscovered.
        png=$out/inga-$state-$size.png
        "$CHROME" --headless --disable-gpu --hide-scrollbars \
            --force-device-scale-factor=1 \
            --window-size="$size,$size" \
            --default-background-color=00000000 \
            --screenshot="$png" \
            "file://$PWD/$sized" >/dev/null 2>&1
        [ -s "$png" ] || { echo "ABBRUCH: $png nicht geschrieben." >&2; exit 1; }

        # A non-empty file is NOT a rendered icon. With a relative path
        # in the file:// URL Chrome reads "build" as a host name, loads
        # nothing, and screenshots a blank white page -- twelve files,
        # exit 0, and every one of them empty (measured 2026-09-10).
        # The tell is the colour type: a transparent background gives
        # RGBA (6); an opaque white page has no alpha to keep and comes
        # out RGB (2). Byte 25 of a PNG is the IHDR colour type.
        colour=$(od -An -tu1 -j25 -N1 "$png" | tr -d ' ')
        [ "$colour" = "6" ] || {
            echo "ABBRUCH: $png hat colortype $colour statt 6 (RGBA) --" >&2
            echo "         der Grund war weiss, es wurde nichts gerendert." >&2
            exit 1
        }
        echo "$png  <-  $src"
    done
done
