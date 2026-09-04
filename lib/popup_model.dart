// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The popup's view logic, pure and DOM-free (specification section 7).
///
/// `web/popup.dart` renders what these functions return; everything
/// with a decision in it lives here, where `dart test` reaches it.
library;

import 'package:webext/browserkit.dart';
import 'package:webext/fmtkit.dart';
import 'package:webext/netkit.dart';

import 'detection.dart';
import 'settings.dart';

/// One rendered block of the header view.
///
/// A plain request has one section without a label. A redirect chain
/// has one section per hop, each labelled -- the specification wants
/// the individual hops visible in the header view (section 6).
final class HeaderSection {
  /// Builds a section.
  const HeaderSection({required this.hopLabel, required this.headers});

  /// The hop line above the block, or null when the chain has one hop.
  final String? hopLabel;

  /// The headers of this block, after filter, collapse and sort.
  /// Unmodifiable.
  final List<HttpHeader> headers;
}

/// The requests in selector order: the main document first, the rest in
/// arrival order (specification section 7).
List<CapturedRequest> selectorOrder(List<CapturedRequest> requests) {
  final main = <CapturedRequest>[];
  final rest = <CapturedRequest>[];
  for (final request in requests) {
    (request.isMainFrame ? main : rest).add(request);
  }
  return List<CapturedRequest>.unmodifiable(<CapturedRequest>[
    ...main,
    ...rest,
  ]);
}

/// The selector entry for one request: method, final address, status.
String requestLabel(CapturedRequest request) {
  final status = request.finalStatusCode;
  return '${request.hops.last.method} ${request.finalUrl} '
      '(${status ?? 'pending'})';
}

/// The header view of one request: per hop one section, each filtered,
/// then collapsed, then sorted -- in that order, so the two settings
/// operate on what the filter left visible.
///
/// [showResponseHeaders] switches between the two sides of section 7.
/// [filter] matches case-insensitively against name and value; empty
/// means everything.
List<HeaderSection> sectionsOf(
  CapturedRequest request, {
  required bool showResponseHeaders,
  required String filter,
  required Settings settings,
}) {
  final singleHop = request.hops.length == 1;
  final sections = <HeaderSection>[];
  for (var index = 0; index < request.hops.length; index += 1) {
    final hop = request.hops[index];
    var headers =
        showResponseHeaders ? hop.responseHeaders : hop.requestHeaders;
    headers = _filtered(headers, filter);
    if (settings.collapseRepeatedHeaders) {
      headers = collapseRepeatedHeaders(headers, _nameOf);
    }
    if (settings.sortHeadersAlphabetically) {
      headers = sortHeadersByName(headers, _nameOf);
    }
    sections.add(HeaderSection(
      hopLabel: singleHop
          ? null
          : '${hop.method} ${hop.url} (${hop.statusCode ?? 'pending'})',
      headers: headers,
    ));
  }
  return List<HeaderSection>.unmodifiable(sections);
}

/// How many headers the view shows, across all sections.
int headerCount(List<HeaderSection> sections) {
  var count = 0;
  for (final section in sections) {
    count += section.headers.length;
  }
  return count;
}

/// The one-header copy text of a row click: `name: value`.
String headerLine(HttpHeader header) => '${header.name}: ${header.value}';

/// The whole-view copy text: a head block (method, status, address,
/// capture time), an empty line, then the view as displayed -- hop
/// labels included, one line per header.
String copyText(
  CapturedRequest request,
  List<HeaderSection> sections, {
  required DateTime Function(double epochMilliseconds) toLocalTime,
}) {
  final startedAt = request.startedAt;
  final head = <String>[
    request.hops.last.method,
    '${request.finalStatusCode ?? 'pending'}',
    request.finalUrl,
    if (startedAt != null) formatClockTime(toLocalTime(startedAt)),
  ];
  final lines = <String>[head.join(' '), ''];
  for (final section in sections) {
    if (section.hopLabel != null) {
      lines.add(section.hopLabel!);
    }
    for (final header in section.headers) {
      lines.add(headerLine(header));
    }
  }
  return lines.join('\n');
}

/// The signal badge opening the Cloudflare line.
enum CloudflareLineBadge {
  /// The final answer said `server: cloudflare`.
  cloudflare,

  /// The final answer said something else -- shown expressly, the line
  /// never stays empty (decision of 2026-09-01).
  notCloudflare,

  /// The selected request has no final answer yet.
  pending,
}

/// One field of the Cloudflare line: a muted spelled-out label and
/// its value.
///
/// A field without a label (`local address`, `no answer yet`) renders
/// its value alone.
final class CloudflareField {
  /// Builds a field.
  const CloudflareField(this.label, this.value);

  /// The muted label, or null for a bare value.
  final String? label;

  /// The value, in full text colour.
  final String value;
}

/// The Cloudflare line under the request selector (one continuous
/// label/value table, ordered 2026-09-01, replacing the two-column
/// grid): the colour dot with the signal word, then one field per row
/// with a shared label column; the on-click trace fields join the same
/// table beneath a divider.
final class CloudflareLine {
  /// Builds a line.
  const CloudflareLine({required this.badge, required this.fields});

  /// The signal opening the line: dot colour and word.
  final CloudflareLineBadge badge;

  /// The fields in display order, one per table row. Unmodifiable.
  final List<CloudflareField> fields;
}

/// The Cloudflare line of one request.
///
/// [pageProtocol] is the negotiated protocol of the PAGE's main
/// document (`nextHopProtocol` of its navigation entry, read on popup
/// open, ADR-003). It renders as `protocol` only when [request] IS the
/// main document -- on a sub-request the line must not claim the
/// document's protocol -- and only when it is non-empty: an empty
/// string is the browser's "not measurable" and shows nothing. The
/// value describes the last hop alone, never a redirect chain.
///
/// Every absent input drops its field silently -- no dash placeholders.
/// A non-Cloudflare answer says so expressly and shows server header,
/// address and timing; an unanswered request reads `no answer yet`.
/// The cache age carries the spec section 5 note when the status is
/// HIT and age is absent.
CloudflareLine cloudflareLineOf(
  CapturedRequest request, {
  String? pageProtocol,
}) {
  if (request.finalStatusCode == null) {
    return const CloudflareLine(
      badge: CloudflareLineBadge.pending,
      fields: <CloudflareField>[
        CloudflareField(null, 'no answer yet'),
      ],
    );
  }

  final detection = CloudflareDetection.of(request);
  final protocolField =
      request.isMainFrame && pageProtocol != null && pageProtocol.isNotEmpty
          ? CloudflareField('protocol', pageProtocol)
          : null;
  final ttfbMilliseconds = request.timeToFirstByteMilliseconds;
  final ttfbSeconds = ttfbMilliseconds == null
      ? null
      : formatTimeToFirstByteSeconds(ttfbMilliseconds);
  final ttfbField =
      ttfbSeconds == null ? null : CloudflareField('ttfb', '$ttfbSeconds s');

  // The display form of the address is what the browser reported (the
  // compressed v6 text), not the parser's uncompressed diagnostic form.
  final rawAddress = request.ip;
  final addressField = rawAddress == null
      ? null
      : CloudflareField(
          'address',
          detection.address == null
              ? rawAddress
              : '$rawAddress (${detection.address!.versionLabel})',
        );

  if (!detection.servedThroughCloudflare) {
    // No range mark here: the range check CONFIRMS the Cloudflare
    // signal, and "not confirmed" against a non-Cloudflare answer would
    // state the obvious as if it were a finding. The local mark stays.
    return CloudflareLine(
      badge: CloudflareLineBadge.notCloudflare,
      // Address last, as ordered 2026-09-01.
      fields: List<CloudflareField>.unmodifiable(<CloudflareField>[
        if (detection.serverHeader != null)
          CloudflareField('server', detection.serverHeader!),
        if (protocolField != null) protocolField,
        if (detection.addressIsLocal)
          const CloudflareField(null, 'local address'),
        if (ttfbField != null) ttfbField,
        if (addressField != null) addressField,
      ]),
    );
  }

  final CloudflareField? rangeField;
  if (detection.address == null) {
    rangeField = null;
  } else if (detection.addressIsLocal) {
    rangeField = const CloudflareField('range', 'local address');
  } else if (detection.addressConfirms) {
    rangeField = const CloudflareField('range', 'confirmed');
  } else {
    rangeField = const CloudflareField('range', 'not confirmed');
  }

  final cacheStatus = detection.cacheStatus;
  final age = detection.age;
  final CloudflareField? ageField;
  if (age != null) {
    ageField = CloudflareField('cache age', '$age s');
  } else if (cacheStatus != null && cacheStatus.toUpperCase() == 'HIT') {
    // Spec section 5: age is absent on an upper tier cache hit.
    ageField = const CloudflareField('cache age', 'absent (upper tier hit)');
  } else {
    ageField = null;
  }

  return CloudflareLine(
    badge: CloudflareLineBadge.cloudflare,
    // Order as approved 2026-09-01: ray id, then data centre and cache
    // status side by side, cache details, range and ttfb -- the address
    // closes the block.
    fields: List<CloudflareField>.unmodifiable(<CloudflareField>[
      if (detection.rayId != null) CloudflareField('ray id', detection.rayId!),
      if (detection.colo != null)
        CloudflareField('data centre', detection.colo!),
      if (cacheStatus != null) CloudflareField('cache status', cacheStatus),
      if (ageField != null) ageField,
      if (detection.browserIsolationVersion != null)
        CloudflareField(
          'browser isolation',
          detection.browserIsolationVersion!,
        ),
      if (protocolField != null) protocolField,
      if (rangeField != null) rangeField,
      if (ttfbField != null) ttfbField,
      if (addressField != null) addressField,
    ]),
  );
}

/// The one-field copy text of a click on a Cloudflare field:
/// `label: value`, or the bare value for an unlabelled field --
/// the same shape a header row copies (requested 2026-09-01).
String cloudflareFieldLine(CloudflareField field) {
  final label = field.label;
  return label == null ? field.value : '$label: ${field.value}';
}

/// The style class of the status badge, coloured by class
/// (specification section 7).
String statusClass(int? statusCode) {
  if (statusCode == null || statusCode < 100 || statusCode > 599) {
    return 'status-none';
  }
  return 'status-${statusCode ~/ 100}xx';
}

List<HttpHeader> _filtered(List<HttpHeader> headers, String filter) {
  final needle = filter.trim().toLowerCase();
  if (needle.isEmpty) {
    return headers;
  }
  return List<HttpHeader>.unmodifiable(headers.where(
    (header) =>
        header.name.toLowerCase().contains(needle) ||
        header.value.toLowerCase().contains(needle),
  ));
}

String _nameOf(HttpHeader header) => header.name;
