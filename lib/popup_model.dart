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
  const CloudflareField(this.label, this.value, {this.hint});

  /// The muted label, or null for a bare value.
  final String? label;

  /// The value, in full text colour.
  final String value;

  /// The explanation of the row, or null.
  ///
  /// NOT a native tooltip, although it was one until 2026-09-11: the
  /// popup draws the box itself, above the row, opened by a `?` marker
  /// in the label. A native `title` waits about a second and is placed
  /// under the pointer -- where the row's copy cursor draws its plus
  /// badge, which then covers the first words -- and neither the delay
  /// nor the placement can be changed.
  ///
  /// For a note that would crowd the row but helps whoever wonders --
  /// a likely cause, a pointer to a bug. The VALUE has to stand on its
  /// own regardless: the box needs a mouse and the suspicion that
  /// there is something to aim at, which is exactly what a reader who
  /// is confused does not have. It is also not built at all when the
  /// explanations are switched off, which is the default.
  final String? hint;
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

/// The unlabelled mark on a non-Cloudflare answer from a machine on the
/// own network (spec section 5: "recognised and marked as local").
const CloudflareField _localAddressNote = CloudflareField(
  null,
  'local address',
  hint: 'The server address is not publicly routable -- a machine on '
      'your own network, not a foreign one.',
);

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
        CloudflareField(
          null,
          'no answer yet',
          hint: 'The selected request has not been answered yet, so there '
              'is nothing to report about it.',
        ),
      ],
    );
  }

  final detection = CloudflareDetection.of(request);
  // Every field carries a hint. Some of them look self-explanatory and
  // are not: `range` says what it does NOT decide, `data centre` and
  // `protocol` say that the trace row below reports the same thing for
  // a different connection. Half the rows explaining themselves and
  // half not is worse than neither (ordered 2026-09-11).
  final protocolField =
      request.isMainFrame && pageProtocol != null && pageProtocol.isNotEmpty
          ? CloudflareField(
              'protocol',
              pageProtocol,
              hint: 'The protocol the PAGE used, read from its own '
                  'navigation entry. The trace row reports the protocol '
                  'of that fetch, which can differ.',
            )
          : null;
  final ttfbMilliseconds = request.timeToFirstByteMilliseconds;
  final ttfbSeconds = ttfbMilliseconds == null
      ? null
      : formatTimeToFirstByteSeconds(ttfbMilliseconds);
  final ttfbField = ttfbSeconds == null
      ? null
      : CloudflareField(
          'ttfb',
          '$ttfbSeconds s',
          hint: 'Time to first byte: from sending the request to the '
              'first byte of the answer arriving.',
        );

  // The display form of the address is what the browser reported (the
  // compressed v6 text), not the parser's uncompressed diagnostic form.
  final rawAddress = detection.addressText;
  final CloudflareField? addressField;
  if (rawAddress == null) {
    addressField = null;
  } else if (detection.addressNamesNoHost) {
    // ADR-004: the browser answered, and its answer names no host. The
    // row says exactly that and carries the raw value, so the reader
    // can check it; the range field stays away, because there is
    // nothing to confirm.
    //
    // The hint is worded in three steps, and each is as strong as its
    // evidence and no stronger. What HAPPENED is certain: the browser
    // sent this. What MAY have caused it is offered as a possibility:
    // Inga cannot see a proxy (no `proxy` permission, and none
    // wanted), so a proxy is never a finding here. And only the ONE
    // documented case is named: Firefox, per its own bug. Chrome
    // behind a proxy is NOT measured, so this text must not read as if
    // it were -- the same file ships in both builds.
    addressField = CloudflareField(
      'address',
      'none reported (browser said $rawAddress)',
      hint: 'The browser sent this instead of an address. A proxy in '
          'front of it can cause that; Firefox is documented to do so '
          '(Mozilla bug 1445279).',
    );
  } else {
    addressField = CloudflareField(
      'address',
      detection.address == null
          ? rawAddress
          : '$rawAddress (${detection.address!.versionLabel})',
      hint: 'The address of the SERVER that answered, as the browser '
          'reported it. Your own address is in the trace row, as '
          '`your ip`.',
    );
  }

  if (!detection.servedThroughCloudflare) {
    // No range mark here: the range check CONFIRMS the Cloudflare
    // signal, and "not confirmed" against a non-Cloudflare answer would
    // state the obvious as if it were a finding. The local mark stays.
    return CloudflareLine(
      badge: CloudflareLineBadge.notCloudflare,
      // Address last, as ordered 2026-09-01.
      fields: List<CloudflareField>.unmodifiable(<CloudflareField>[
        if (detection.serverHeader != null)
          CloudflareField(
            'server',
            detection.serverHeader!,
            hint: 'The Server response header, verbatim as the answer '
                'carried it. This is the signal that decides whether a '
                'site counts as served through Cloudflare.',
          ),
        if (protocolField != null) protocolField,
        if (detection.addressIsLocal) _localAddressNote,
        if (ttfbField != null) ttfbField,
        if (addressField != null) addressField,
      ]),
    );
  }

  final CloudflareField? rangeField;
  if (detection.address == null) {
    rangeField = null;
  } else if (detection.addressIsLocal) {
    rangeField = const CloudflareField(
      'range',
      'local address',
      hint: 'The server address is not publicly routable -- a machine on '
          'your own network, not a foreign one.',
    );
  } else if (detection.addressConfirms) {
    rangeField = const CloudflareField(
      'range',
      'confirmed',
      hint: 'The server address lies inside the ranges Cloudflare '
          'publishes. This CONFIRMS the server header; the header is '
          'what decides.',
    );
  } else {
    rangeField = const CloudflareField(
      'range',
      'not confirmed',
      hint: 'The server address lies outside the ranges compiled into '
          'this build. That costs a confirmation, never a verdict: the '
          'server header decides, and a range list can be out of date.',
    );
  }

  final cacheStatus = detection.cacheStatus;
  final age = detection.age;
  final CloudflareField? ageField;
  if (age != null) {
    ageField = CloudflareField(
      'cache age',
      '$age s',
      hint: 'How long Cloudflare has been holding this cached copy, in '
          'seconds.',
    );
  } else if (cacheStatus != null && cacheStatus.toUpperCase() == 'HIT') {
    // Spec section 5: age is absent on an upper tier cache hit.
    ageField = const CloudflareField(
      'cache age',
      'absent (upper tier hit)',
      hint: 'A HIT without an age header: Cloudflare sends none when the '
          'copy came from an upper tier cache rather than this data '
          'centre.',
    );
  } else {
    ageField = null;
  }

  return CloudflareLine(
    badge: CloudflareLineBadge.cloudflare,
    // Order as approved 2026-09-01: ray id, then data centre and cache
    // status side by side, cache details, range and ttfb -- the address
    // closes the block.
    fields: List<CloudflareField>.unmodifiable(<CloudflareField>[
      if (detection.rayId != null)
        CloudflareField(
          'ray id',
          detection.rayId!,
          hint: 'The Cloudflare request id, shown in full because it is '
              'the ticket for a Cloudflare support case. Its suffix is '
              'the data centre.',
        ),
      if (detection.colo != null)
        CloudflareField(
          'data centre',
          detection.colo!,
          hint: 'The Cloudflare data centre that answered the PAGE, read '
              'from the cf-ray suffix. The trace row reports the one that '
              'answered that fetch, and a difference is normal.',
        ),
      if (cacheStatus != null)
        CloudflareField(
          'cache status',
          cacheStatus,
          hint: 'What the Cloudflare cache did: HIT served from cache, '
              'MISS fetched from the origin, DYNAMIC not cacheable, '
              'EXPIRED revalidated, BYPASS cache deliberately skipped.',
        ),
      if (ageField != null) ageField,
      if (detection.browserIsolationVersion != null)
        CloudflareField(
          'browser isolation',
          detection.browserIsolationVersion!,
          hint: 'The page was rendered remotely at Cloudflare rather '
              'than on this device (cf-biso-version header).',
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
