// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The external check tools reachable from the popup's header menu
/// (ADR-002): name and hand-over URL per tool, built from the page's
/// HOSTNAME alone -- path and query of the page never travel.
///
/// Inga fetches nothing here. A click opens a browser tab; the tool
/// loads in that tab's own context. The four URL forms are HARD-CODED
/// by decision (2026-09-02): no setting, so there is no place a
/// foreign address could be planted. Each form was measured against
/// the live tool on 2026-09-02:
///
/// - SSL Labs: the start page form is `GET analyze.html` with field
///   `d` and the checkbox `name="hideResults"` labelled "Do not show
///   the results on the boards" -- a GET checkbox sends
///   `hideResults=on`, so the link carries it: the result never lands
///   on the public boards. The MDN Observatory form renders
///   client-side without a single input in the static HTML; no
///   equivalent option is measurable there, its URL stays bare.
/// - Mozilla Observatory: `observatory.mozilla.org` 301s to MDN; the
///   `analyze?host=` route answers 200.
/// - DNSViz: the start page form `GET /search/?d=` 302s to
///   `/d/<host>/`, which is used directly.
/// - Verisign DNSSEC Debugger: the path form answers 200 with the
///   analysis for that host.
library;

import 'package:webext/netkit.dart';

/// One external check: menu label and the URL a click opens.
final class ExternalCheck {
  /// Builds a check entry.
  const ExternalCheck(this.name, this.url);

  /// The menu label.
  final String name;

  /// The full URL, hostname already embedded and encoded.
  final String url;
}

/// The host the external checks are aimed at: the hostname of the
/// tab's main document, or null when there is no main document or its
/// origin is not http(s) -- the menu button stays disabled then.
String? checkHostOf(List<CapturedRequest> requests) {
  for (final request in requests) {
    if (!request.isMainFrame) {
      continue;
    }
    final Uri parsed;
    try {
      parsed = Uri.parse(request.finalUrl);
    } on FormatException {
      return null;
    }
    if (parsed.scheme != 'http' && parsed.scheme != 'https') {
      return null;
    }
    if (parsed.host.isEmpty) {
      return null;
    }
    return parsed.host;
  }
  return null;
}

/// The four checks for [host], in menu order. Empty for an empty host.
List<ExternalCheck> externalChecks(String host) {
  if (host.isEmpty) {
    return const <ExternalCheck>[];
  }
  final encoded = Uri.encodeComponent(host);
  return List<ExternalCheck>.unmodifiable(<ExternalCheck>[
    ExternalCheck(
      'SSL Labs',
      'https://www.ssllabs.com/ssltest/analyze.html'
          '?d=$encoded&hideResults=on',
    ),
    ExternalCheck(
      'Mozilla Observatory',
      'https://developer.mozilla.org/en-US/observatory/analyze?host=$encoded',
    ),
    ExternalCheck('DNSViz', 'https://dnsviz.net/d/$encoded/'),
    ExternalCheck(
      'DNSSEC Debugger',
      'https://dnssec-debugger.verisignlabs.com/$encoded',
    ),
  ]);
}
