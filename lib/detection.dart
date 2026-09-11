// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Cloudflare detection: the two independent signals of the
/// specification, section 5, evaluated locally over a captured request.
///
/// The `server` response header is the PRIMARY signal; the server
/// address confirms it. A stale compiled-in range list therefore costs a
/// confirmation mark, never a false negative. Nothing here performs a
/// request -- every input is what `webRequest` delivered anyway.
library;

import 'package:webext/browserkit.dart';
import 'package:webext/fmtkit.dart';
import 'package:webext/netkit.dart';

/// What the two signals said about one captured request.
final class CloudflareDetection {
  const CloudflareDetection._({
    required this.servedThroughCloudflare,
    required this.rayId,
    required this.colo,
    required this.cacheStatus,
    required this.age,
    required this.browserIsolationVersion,
    required this.addressConfirms,
    required this.addressIsLocal,
    required this.serverHeader,
    required this.address,
    required this.addressText,
    required this.addressNamesNoHost,
  });

  /// The primary signal: the final answer carried `server: cloudflare`
  /// (both sides compared case-insensitively, the value trimmed).
  final bool servedThroughCloudflare;

  /// The request id from the `cf-ray` header, or null when the header
  /// is absent or does not parse (fmtkit reports that as an absent
  /// value, ADR-006 of the library). Shown in full: it is the ticket
  /// for a Cloudflare support case.
  final String? rayId;

  /// The data centre code from the `cf-ray` suffix, or null when the
  /// header is absent or does not parse.
  final String? colo;

  /// The raw `cf-cache-status` value -- HIT, MISS, DYNAMIC, EXPIRED
  /// (spec section 5) -- or null when the answer carried none.
  final String? cacheStatus;

  /// The raw `age` value, or null when the answer carried none. Spec
  /// section 5: absent on an upper tier cache hit.
  final String? age;

  /// The raw `cf-biso-version` value: remote browser isolation in use
  /// (spec section 5). Null when the answer carried none.
  final String? browserIsolationVersion;

  /// The confirming signal: the server address lies inside Cloudflare's
  /// published ranges. False when there is no address or it does not
  /// parse.
  final bool addressConfirms;

  /// The address is not publicly routable -- a development host, not a
  /// foreign one (spec section 5: "recognised and marked as local").
  final bool addressIsLocal;

  /// The raw `server` header value of the final answer, or null when
  /// the answer carried none. Display material for the tooltip's second
  /// line.
  final String? serverHeader;

  /// The parsed server address, or null when the browser reported none,
  /// the value did not parse, or it names no host (see [of]).
  final IpAddress? address;

  /// The address text exactly as the browser reported it, or null when
  /// it reported none at all.
  ///
  /// Not null for a value the parser rejects, and not null for one that
  /// names no host: both are the browser's own word, and hiding it says
  /// less than showing it. What the display makes of them differs --
  /// see [addressNamesNoHost].
  final String? addressText;

  /// The browser reported an address, and it names no host (see [of]).
  ///
  /// The display keeps the row and says so, with the raw value in
  /// brackets; it does NOT drop the row. A dropped row is
  /// indistinguishable from a build that has no address row at all, and
  /// a reader who cannot tell those apart learns nothing from the
  /// silence -- observed on a live popup, 2026-09-10, where exactly
  /// that question came back (ADR-004, amended the same day).
  final bool addressNamesNoHost;

  /// Evaluates both signals over [request].
  ///
  /// The headers of the FINAL answer are the response headers of the
  /// last hop -- the chain keeps one entry per request and the last hop
  /// is the one that answered with the first byte (library ADR-005).
  ///
  /// An address that names no host (`_namesNoHost`) is no answer to
  /// the question which server replied: [address] falls to null, so the
  /// version mark and the range field drop out rather than reporting a
  /// measurement that never took place (ADR-004). [addressText] keeps
  /// the raw value and [addressNamesNoHost] is set, so the display can
  /// say what happened instead of falling silent.
  static CloudflareDetection of(CapturedRequest request) {
    final headers = request.hops.last.responseHeaders;
    final serverHeader = _firstValue(headers, 'server');
    final rayHeader = _firstValue(headers, 'cf-ray');
    final ray = rayHeader == null ? null : CfRay.tryParse(rayHeader);
    final reported = request.ip;
    final parsed = reported == null ? null : IpAddress.tryParse(reported);
    final namesNoHost = parsed != null && _namesNoHost(parsed);
    final address = namesNoHost ? null : parsed;
    return CloudflareDetection._(
      servedThroughCloudflare: serverHeader != null &&
          serverHeader.trim().toLowerCase() == 'cloudflare',
      rayId: ray?.rayId,
      colo: ray?.colo,
      cacheStatus: _firstValue(headers, 'cf-cache-status'),
      age: _firstValue(headers, 'age'),
      browserIsolationVersion: _firstValue(headers, 'cf-biso-version'),
      addressConfirms: address != null && isCloudflareAddress(address),
      addressIsLocal: address != null && address.isNonPublic,
      serverHeader: serverHeader,
      address: address,
      addressText: reported,
      addressNamesNoHost: namesNoHost,
    );
  }

  /// The first value of the header called [name], compared
  /// case-insensitively; null when no header carries the name.
  static String? _firstValue(List<HttpHeader> headers, String name) {
    for (final header in headers) {
      if (header.name.toLowerCase() == name) {
        return header.value;
      }
    }
    return null;
  }
}

/// Whether [address] names no host, and is therefore no answer to the
/// question which server replied.
///
/// Two shapes qualify. `0.0.0.0/8` is "this network" (RFC 1122 section
/// 3.2.1.3): a source address for a host that does not yet know its
/// own, never a destination. The IPv6 `::` is the unspecified address
/// of RFC 4291 section 2.5.2 and means the same; there it is that one
/// address, not a block.
///
/// The measured way they arrive here is Firefox behind a SOCKS proxy,
/// which reports `0.0.0.0` in the `webRequest` details -- the
/// connection has no peer address it could name (Mozilla bug 1445279,
/// UNCONFIRMED and unresolved when read on 2026-09-10; its comment 3
/// records the same value reaching the `webRequest` `ip` property,
/// which is what makes it this code's reference rather than a report
/// about the network monitor).
///
/// The test below is deliberately about the ADDRESS, not about that
/// browser: a value out of these blocks names no host whoever sent it.
/// Chrome behind a proxy is NOT measured -- if it does the same, this
/// already covers it, and if it does something else, nothing here
/// claims otherwise.
/// Passed through, it would print `0.0.0.0` as the server address and
/// answer the range check with "not confirmed", which asserts a
/// measurement that never happened. Read as absent, it lands in the
/// case the specification already words -- "the browser reports no
/// server address", section 4.
bool _namesNoHost(IpAddress address) => switch (address) {
      IpV4Address(:final octets) => octets[0] == 0,
      IpV6Address(:final groups) => groups.every((group) => group == 0),
    };
