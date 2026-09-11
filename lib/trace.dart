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

/// The heading over the trace fields, carrying the local clock time
/// [when] at which the fetch was fired.
///
/// The time is there because a repeated click REPLACES the previous
/// answer in place (see the popup's `_fillTraceRow`): without it the
/// table cannot say whether the values below were fetched a second ago
/// or ten minutes ago, and the passive fields above keep changing
/// under them as the reader switches requests. Asked for 2026-09-11.
///
/// [when] is formatted as given -- no conversion. The caller passes
/// local time; keeping the conversion out here is what makes the
/// function testable without a time zone.
///
/// Seconds are shown, not just hours and minutes: two trace fetches a
/// minute apart are the normal case when one is comparing data
/// centres, and a heading that reads the same for both answers the
/// question wrongly rather than not at all.
String traceHeading(DateTime when) => 'trace request '
    '${_twoDigits(when.hour)}:${_twoDigits(when.minute)}'
    ':${_twoDigits(when.second)}';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

/// The displayed fields of a trace answer, in display order, or an
/// empty list when the body carries none of the expected keys -- the
/// caller then reports an unexpected answer instead of a bare row.
///
/// The answer is `key=value` lines. Nine keys are displayed and
/// everything else is ignored. The values describe the TRACE request,
/// not the page (ADR-001, decision 4) -- the caller renders them under
/// the `trace request:` marker.
///
/// Two of them, `protocol` and `colo`, are also shown passively above,
/// read from the page's own answer. That doubling is DELIBERATE: the
/// passive value describes the page load, the trace value this fetch,
/// and where they differ that difference is the finding. Both differed
/// in one popup on 2026-09-11 -- the page came over `h3` from `BRU`,
/// the trace over `http/2` from `CDG`. Do NOT remove either as a
/// duplicate; the argument that the passive value makes the trace one
/// redundant was made in that session and refuted by that screenshot.
///
/// Every field carries a hint, because none of these labels explains
/// itself and several are read wrongly by default -- `warp` says
/// nothing about proxies other than Cloudflare's own, and `your ip` is
/// an exit address whenever anything sits in between.
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
  // Order: how the connection was made, who carried it, and who you
  // are at the far end. The first five are the table of 2026-09-01;
  // kex, gateway, rbi and your country joined on 2026-09-11.
  return List<CloudflareField>.unmodifiable(<CloudflareField>[
    if (values['http'] != null)
      CloudflareField(
        'protocol',
        values['http']!,
        hint: 'The protocol this trace fetch used. The protocol shown '
            'above is the one the page itself used; the two can differ.',
      ),
    if (values['tls'] != null)
      CloudflareField(
        'tls',
        values['tls']!,
        hint: 'The TLS version of this trace fetch.',
      ),
    if (values['kex'] != null)
      CloudflareField(
        'kex',
        values['kex']!,
        hint: 'The key exchange of this trace fetch. A name containing '
            'MLKEM is a post-quantum hybrid.',
      ),
    if (values['colo'] != null)
      CloudflareField(
        'colo',
        values['colo']!,
        hint: 'The Cloudflare data centre that answered this fetch. The '
            'data centre shown above answered the page; the two can '
            'differ, and a difference is normal.',
      ),
    if (values['warp'] != null)
      CloudflareField(
        'warp',
        values['warp']!,
        hint: 'Whether this request came through Cloudflare WARP, the '
            'tunnel Cloudflare provides itself. It says nothing about any '
            'other proxy: those are invisible here.',
      ),
    if (values['gateway'] != null)
      CloudflareField(
        'gateway',
        values['gateway']!,
        hint: 'Whether Cloudflare Gateway applied the policy of an '
            'organisation to this request. Where it also inspects TLS, '
            'the headers above come from Gateway, not from the origin '
            'server.',
      ),
    if (values['rbi'] != null)
      CloudflareField(
        'rbi',
        values['rbi']!,
        hint: 'Whether the page runs in a remote isolated browser at '
            'Cloudflare rather than on this device.',
      ),
    if (values['ip'] != null)
      CloudflareField(
        'your ip',
        values['ip']!,
        hint: 'The address Cloudflare sees YOU under. Behind WARP or any '
            'other proxy this is the exit address, not your own.',
      ),
    if (values['loc'] != null)
      CloudflareField(
        'your country',
        values['loc']!,
        hint: 'The country Cloudflare derives from that address -- not '
            'from your device, and not the country the data centre '
            'stands in.',
      ),
  ]);
}
