// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The explanation the header list carries, the counterpart of the
/// hints the Cloudflare fields carry.
///
/// **One header, not nine.** A first attempt explained nine of them --
/// alt-svc, cf-cache-status, cf-ray, nel, report-to,
/// strict-transport-security, vary, content-encoding, age -- and that
/// was rejected on sight (project lead, 2026-09-11): on a typical
/// Cloudflare answer most of them apply at once, so a list of about
/// twenty rows grew eight question marks and read as clutter. The
/// header list is scanned, not studied, and a marker on every other row
/// defeats scanning. `cf-ray` was named as expressly unwanted.
///
/// The one that stays is the one that says the OPPOSITE of what it is
/// read as. The other eight explained headers that are merely unknown,
/// which a reader can look up; `alt-svc` misleads a reader who already
/// knows what he is looking at. Their texts are not lost -- they are in
/// commit 9fc8990, should one of them ever earn its place back.
///
/// The rules the text keeps are the ones the Cloudflare hints keep: it
/// claims no cause it cannot see, it says what the value is NOT, and
/// the header VALUE stands on its own regardless -- a hint needs a
/// mouse and the suspicion that there is something to aim at.
library;

/// The explanation for the header [name], or null when it has none --
/// which is every header but one.
///
/// [name] is matched case-insensitively after trimming: HTTP header
/// names are case-insensitive, and a capture carries them as the wire
/// had them -- lower case over HTTP/2 and HTTP/3, mixed case over
/// HTTP/1.1. A lookup that missed `Alt-Svc` while finding `alt-svc`
/// would explain the same header on one site and not on the next.
String? headerHint(String name) => _hints[name.trim().toLowerCase()];

const Map<String, String> _hints = <String, String>{
  'alt-svc': 'An OFFER of another route, not a measurement of this '
      'request. `h3=":443"; ma=86400` says: I also speak HTTP/3 on port '
      '443, remember that for 86400 seconds. It is why the same site '
      'can show h2 now and h3 on the next visit.',
};
