// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// What the toolbar shows per tab: icon state, badge, tooltip -- derived
/// from the captured requests alone, so the worker can recompute it from
/// storage at any time (specification sections 2 to 4).
library;

import 'package:webext/fmtkit.dart';
import 'package:webext/netkit.dart';

import 'detection.dart';

/// The three toolbar states of specification section 2.
///
/// Named after the artwork since 2026-09-02 (real graphics in
/// `icons/src/`): the RED ladybird is the everyday measured state,
/// orange marks Cloudflare, and the file name for [none] is
/// `neutral` -- the grey beetle.
enum IconState {
  /// Served through Cloudflare.
  orange,

  /// Measured, and not served through Cloudflare.
  red,

  /// Nothing captured yet for this tab.
  none,
}

/// The SHORT extension name, as the toolbar tooltip's fallback.
///
/// Deliberately "Inga", not the long store name the manifest's `name`
/// carries since 2026-09-02: the tooltip fallback stays short. The same
/// string stands in `manifest.json` as `default_title`, and the two
/// places CANNOT be joined: a per-tab title, once set, cannot be cleared
/// back to the manifest default -- measured on Chrome for Testing 152:
/// `setTitle('')` leaves an EMPTY per-tab title (`getTitle` returns
/// `''`), and `title: null` is rejected as a missing property. So the
/// fallback of specification section 4 has to be written explicitly,
/// and this constant is that second place, carrying its reason
/// (TEST-012). Whoever changes the short name changes `default_title`
/// and this line together.
const String extensionName = 'Inga';

/// The badge background while the icon is [IconState.orange]:
/// Cloudflare's orange (decision of 2026-09-01).
const String cloudflareBadgeColor = '#F6821F';

/// The badge background while the icon is [IconState.red]: the red of
/// the not-Cloudflare beetle (decision of 2026-09-01), so the badge
/// does not sit grey on red wing covers.
const String redBadgeColor = '#FF3B30';

/// Everything the worker sets on the toolbar for one tab.
///
/// Absent values mean "reset": an empty [badgeText] removes the badge,
/// a null [tooltip] means the [extensionName] fallback of specification
/// section 4, and [IconState.none] points at the default icon.
final class TabPresentation {
  const TabPresentation._({
    required this.iconState,
    required this.badgeText,
    required this.badgeColor,
    required this.tooltip,
  });

  /// Which of the three icons the tab shows.
  final IconState iconState;

  /// The badge text, or the empty string to remove the badge.
  final String badgeText;

  /// The badge background color, or null when there is no badge.
  final String? badgeColor;

  /// The two tooltip lines of specification section 4, or null to fall
  /// back to the extension name.
  final String? tooltip;

  /// Derives the presentation of one tab from its captured [requests].
  ///
  /// [toLocalTime] turns an epoch timestamp in milliseconds into the
  /// wall-clock time the first tooltip line shows; production passes
  /// `DateTime.fromMillisecondsSinceEpoch`, tests pass something fixed
  /// so the expected strings do not depend on the machine's time zone.
  ///
  /// [showTimeToFirstByte] is the settings checkbox of 2026-09-01
  /// (revised the same day): off suppresses the TIMING -- the badge
  /// number and the ttfb part of the tooltip's first line -- while the
  /// rest of the tooltip stays on the hover and the icon colour keeps
  /// reporting the Cloudflare detection; that signal is never switched
  /// off.
  static TabPresentation of(
    List<CapturedRequest> requests, {
    required DateTime Function(double epochMilliseconds) toLocalTime,
    bool showTimeToFirstByte = true,
  }) {
    final mainDocument = _mainDocumentOf(requests);
    if (mainDocument == null || mainDocument.finalStatusCode == null) {
      // Nothing captured, or the answer has not arrived: the default
      // state, badge and tooltip reset.
      return const TabPresentation._(
        iconState: IconState.none,
        badgeText: '',
        badgeColor: null,
        tooltip: null,
      );
    }

    final detection = CloudflareDetection.of(mainDocument);
    final iconState =
        detection.servedThroughCloudflare ? IconState.orange : IconState.red;

    if (!showTimeToFirstByte) {
      // The icon keeps reporting, and so does the tooltip -- only the
      // timing is withheld: no badge number, no ttfb part in the first
      // line (revised 2026-09-01; the hover used to go dark entirely).
      return TabPresentation._(
        iconState: iconState,
        badgeText: '',
        badgeColor: null,
        tooltip: _tooltip(
          mainDocument,
          detection,
          toLocalTime: toLocalTime,
          includeTiming: false,
        ),
      );
    }

    final ttfbMilliseconds = mainDocument.timeToFirstByteMilliseconds;
    final badgeText = ttfbMilliseconds == null
        ? ''
        : formatBadgeDuration(ttfbMilliseconds) ?? '';

    return TabPresentation._(
      iconState: iconState,
      badgeText: badgeText,
      badgeColor:
          iconState == IconState.orange ? cloudflareBadgeColor : redBadgeColor,
      tooltip: _tooltip(
        mainDocument,
        detection,
        toLocalTime: toLocalTime,
        includeTiming: true,
      ),
    );
  }

  /// The two lines of specification section 4.
  ///
  /// First line: capture time, IP version, data centre, time to first
  /// byte in seconds. The version is omitted when the browser reported
  /// no usable address, `colo=` is omitted for non-Cloudflare sites, and
  /// the ttfb part is omitted when the value cannot be formatted -- each
  /// silently, as the specification words it.
  ///
  /// Second line: the `server` header value and the status code; without
  /// a `server` header only the status code.
  static String _tooltip(
    CapturedRequest mainDocument,
    CloudflareDetection detection, {
    required DateTime Function(double epochMilliseconds) toLocalTime,
    required bool includeTiming,
  }) {
    final startedAt = mainDocument.startedAt;
    final firstLine = <String>[
      if (startedAt != null) formatClockTime(toLocalTime(startedAt)),
      if (detection.address != null) detection.address!.versionLabel,
      if (detection.servedThroughCloudflare && detection.colo != null)
        'colo=${detection.colo}',
    ];
    final ttfbMilliseconds = mainDocument.timeToFirstByteMilliseconds;
    final ttfbSeconds = !includeTiming || ttfbMilliseconds == null
        ? null
        : formatTimeToFirstByteSeconds(ttfbMilliseconds);
    if (ttfbSeconds != null) {
      firstLine.add('ttfb $ttfbSeconds s');
    }

    final secondLine = <String>[
      if (detection.serverHeader != null) detection.serverHeader!,
      '${mainDocument.finalStatusCode}',
    ];

    return '${firstLine.join(' ')}\n${secondLine.join(' ')}';
  }

  static CapturedRequest? _mainDocumentOf(List<CapturedRequest> requests) {
    for (final request in requests) {
      if (request.isMainFrame) {
        return request;
      }
    }
    return null;
  }
}

/// The packaged icon paths for [state], keyed by pixel size, as
/// `ActionApi.setIcon` takes them. One place owns the file names.
///
/// ROOT-absolute on purpose (leading slash): the worker lives under
/// `build/`, and Chrome resolves a relative `setIcon` path against the
/// CALLER's location, not the extension root -- measured 2026-09-01,
/// every `setIcon('icons/...')` from the worker failed with
/// `Failed to fetch` because `build/icons/` does not exist. Manifest
/// paths are root-relative by definition, which is why the same
/// spelling worked there and hid the difference.
Map<String, String> iconPathsOf(IconState state) {
  final name = switch (state) {
    IconState.orange => 'orange',
    IconState.red => 'red',
    IconState.none => 'neutral',
  };
  return <String, String>{
    '16': '/icons/inga-$name-16.png',
    '32': '/icons/inga-$name-32.png',
  };
}
