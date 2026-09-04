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

  /// The parsed server address, or null when the browser reported none
  /// or the value did not parse.
  final IpAddress? address;

  /// Evaluates both signals over [request].
  ///
  /// The headers of the FINAL answer are the response headers of the
  /// last hop -- the chain keeps one entry per request and the last hop
  /// is the one that answered with the first byte (library ADR-005).
  static CloudflareDetection of(CapturedRequest request) {
    final headers = request.hops.last.responseHeaders;
    final serverHeader = _firstValue(headers, 'server');
    final rayHeader = _firstValue(headers, 'cf-ray');
    final ray = rayHeader == null ? null : CfRay.tryParse(rayHeader);
    final address = request.ip == null ? null : IpAddress.tryParse(request.ip!);
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
