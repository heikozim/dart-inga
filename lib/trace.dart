// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The pure half of the on-click `/cdn-cgi/trace` fetch (ADR-001):
/// building the URL from the page's origin, and reading the answer.
///
/// The fetch itself lives in the popup; everything with a decision in
/// it is here, testable without a browser.
library;

import 'popup_model.dart';

/// The trace URL for the page at [pageUrl], or null when no trace
/// request must be made for it.
///
/// Built from the ORIGIN alone -- scheme, host and port. Path and query
/// of the inspected page never travel (ADR-001, decision 3). Only http
/// and https origins qualify; anything else returns null.
String? traceUrlFor(String pageUrl) {
  final Uri parsed;
  try {
    parsed = Uri.parse(pageUrl);
  } on FormatException {
    return null;
  }
  if (parsed.scheme != 'http' && parsed.scheme != 'https') {
    return null;
  }
  if (parsed.host.isEmpty) {
    return null;
  }
  final port = parsed.hasPort ? ':${parsed.port}' : '';
  return '${parsed.scheme}://${parsed.host}$port/cdn-cgi/trace';
}

/// The displayed fields of a trace answer, in display order, or an
/// empty list when the body carries none of the expected keys -- the
/// caller then reports an unexpected answer instead of a bare row.
///
/// The answer is `key=value` lines. Five keys are displayed -- the
/// protocol, TLS version, WARP state, data centre and the user's public
/// address; everything else is ignored. The values describe the TRACE
/// request, not the page (ADR-001, decision 4) -- the caller renders
/// them under the `trace request:` marker.
List<CloudflareField> traceFields(String body) {
  final values = <String, String>{};
  for (final line in body.split('\n')) {
    final separator = line.indexOf('=');
    if (separator <= 0) {
      continue;
    }
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    if (value.isNotEmpty) {
      values[key] = value;
    }
  }
  // Order per the table of 2026-09-01: protocol, tls, colo, warp,
  // your ip.
  return List<CloudflareField>.unmodifiable(<CloudflareField>[
    if (values['http'] != null) CloudflareField('protocol', values['http']!),
    if (values['tls'] != null) CloudflareField('tls', values['tls']!),
    if (values['colo'] != null) CloudflareField('colo', values['colo']!),
    if (values['warp'] != null) CloudflareField('warp', values['warp']!),
    if (values['ip'] != null) CloudflareField('your ip', values['ip']!),
  ]);
}
