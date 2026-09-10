#!/bin/sh
# dart-inga -- Inga, a Manifest V3 header inspector
# Copyright (C) 2026 Heiko Zimmermann
# SPDX-License-Identifier: BSD-3-Clause
#
# Builds the extension. Same path as the library's smoke extension and
# the upstream example of package:chrome_extension: one `dart compile js`
# per entry point; the manifest and the HTML shells point at the produced
# files under build/, which is gitignored.
set -eu
cd "$(dirname "$0")/.."
dart compile js web/background.dart --output build/background.js
dart compile js web/popup.dart --output build/popup.js
dart compile js web/options.dart --output build/options.js
