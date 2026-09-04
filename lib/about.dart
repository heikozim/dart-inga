// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The about block of the options page.
///
/// The version is READ from the packaged manifest at runtime, never
/// maintained a second time (requested 2026-09-01: no double
/// bookkeeping). The options page fetches its own `manifest.json` --
/// a package-internal resource, not an outgoing request -- and this
/// pure half extracts the field, so it is testable without a browser.
library;

import 'dart:convert';

/// The `version` field of a manifest JSON text, or null when the text
/// is not JSON, not an object, or carries no string version -- the
/// caller then omits the version line rather than inventing one
/// (ADR-006 of the library, applied to a parser).
String? versionFromManifestJson(String manifestJson) {
  final Object? decoded;
  try {
    decoded = jsonDecode(manifestJson);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, Object?>) {
    return null;
  }
  final version = decoded['version'];
  return version is String ? version : null;
}
