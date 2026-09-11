// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The settings of specification section 8, and their store.
///
/// The count is deliberately not written down here: it was "three" for
/// long enough to become wrong, and a number in prose has no way of
/// noticing that a field was added (corrected 2026-09-11).
///
/// One storage key in the `sync` area, two places that operate it: the
/// popup's theme switch and the options page. There is no change event
/// on the storage facade, so each page reads on open -- the two are
/// rarely open at once, and a stale view costs one reopen.
library;

import 'package:webext/browserkit.dart';

/// The theme choice: follow the system, or force one side.
enum ThemeSetting {
  /// Follow `prefers-color-scheme`.
  system,

  /// Always light.
  light,

  /// Always dark.
  dark,
}

/// The user-facing settings, immutable.
final class Settings {
  /// Builds a settings value.
  const Settings({
    required this.theme,
    required this.collapseRepeatedHeaders,
    required this.sortHeadersAlphabetically,
    required this.showTimeToFirstByte,
    required this.enableTraceFetch,
    required this.showFieldHints,
  });

  /// What every field is before the user touches anything.
  static const Settings defaults = Settings(
    theme: ThemeSetting.system,
    collapseRepeatedHeaders: false,
    sortHeadersAlphabetically: false,
    showTimeToFirstByte: true,
    enableTraceFetch: false,
    showFieldHints: false,
  );

  /// Light, dark, or follow the system.
  final ThemeSetting theme;

  /// Collapse repeated headers to the first occurrence.
  final bool collapseRepeatedHeaders;

  /// Sort headers alphabetically by name.
  final bool sortHeadersAlphabetically;

  /// Show the time to first byte on the toolbar: the badge number and
  /// the ttfb part of the tooltip. Off withholds only the timing -- the
  /// tooltip keeps its remaining lines, and the icon colour keeps
  /// reporting; the Cloudflare detection itself always runs (decision
  /// of 2026-09-01, revised the same day: the hover used to go dark
  /// entirely; default on, the behaviour the extension shipped with).
  final bool showTimeToFirstByte;

  /// Allow the on-click `/cdn-cgi/trace` fetch -- Inga's ONE outgoing
  /// request, aimed at the origin of the inspected page and fired only
  /// by a click on the `cloudflare` word (ADR-001). Off by default;
  /// with it off, nothing ever leaves the browser.
  final bool enableTraceFetch;

  /// Show the explanation over a Cloudflare field on hover.
  ///
  /// OFF by default, decided 2026-09-11 after living with it on for an
  /// evening. The explanations exist because several labels are read
  /// wrongly without their caveat -- `warp` is not a proxy detector,
  /// `range: not confirmed` is not a verdict -- but that is a lesson
  /// one learns ONCE. Whoever inspects headers for a living has the
  /// labels in their head, and a box that opens on every pass of the
  /// mouse is then only in the way. Default to the person who uses the
  /// tool daily; the newcomer switches them on.
  ///
  /// Off suppresses the boxes entirely -- they are never built, not
  /// merely hidden.
  final bool showFieldHints;

  /// The storage shape of this value.
  Map<String, Object?> encode() => <String, Object?>{
        'theme': theme.name,
        'collapseRepeatedHeaders': collapseRepeatedHeaders,
        'sortHeadersAlphabetically': sortHeadersAlphabetically,
        'showTimeToFirstByte': showTimeToFirstByte,
        'enableTraceFetch': enableTraceFetch,
        'showFieldHints': showFieldHints,
      };

  /// Reads a settings value back from storage.
  ///
  /// Tolerant by design: a missing map, a missing field or a value of
  /// the wrong shape falls back to that field's default. Settings are
  /// preferences, not integrity-critical state -- a corrupt value must
  /// cost a preference, never the popup.
  static Settings decode(Map<String, Object?>? json) {
    if (json == null) {
      return defaults;
    }
    final theme = json['theme'];
    final collapse = json['collapseRepeatedHeaders'];
    final sort = json['sortHeadersAlphabetically'];
    final showTtfb = json['showTimeToFirstByte'];
    final trace = json['enableTraceFetch'];
    final hints = json['showFieldHints'];
    return Settings(
      theme: ThemeSetting.values.asNameMap()[theme] ?? defaults.theme,
      collapseRepeatedHeaders:
          collapse is bool ? collapse : defaults.collapseRepeatedHeaders,
      sortHeadersAlphabetically:
          sort is bool ? sort : defaults.sortHeadersAlphabetically,
      showTimeToFirstByte:
          showTtfb is bool ? showTtfb : defaults.showTimeToFirstByte,
      enableTraceFetch: trace is bool ? trace : defaults.enableTraceFetch,
      showFieldHints: hints is bool ? hints : defaults.showFieldHints,
    );
  }

  /// A copy with the given fields replaced.
  Settings copyWith({
    ThemeSetting? theme,
    bool? collapseRepeatedHeaders,
    bool? sortHeadersAlphabetically,
    bool? showTimeToFirstByte,
    bool? enableTraceFetch,
    bool? showFieldHints,
  }) =>
      Settings(
        theme: theme ?? this.theme,
        collapseRepeatedHeaders:
            collapseRepeatedHeaders ?? this.collapseRepeatedHeaders,
        sortHeadersAlphabetically:
            sortHeadersAlphabetically ?? this.sortHeadersAlphabetically,
        showTimeToFirstByte: showTimeToFirstByte ?? this.showTimeToFirstByte,
        enableTraceFetch: enableTraceFetch ?? this.enableTraceFetch,
        showFieldHints: showFieldHints ?? this.showFieldHints,
      );

  @override
  String toString() => 'Settings(theme: ${theme.name}, '
      'collapseRepeatedHeaders: $collapseRepeatedHeaders, '
      'sortHeadersAlphabetically: $sortHeadersAlphabetically, '
      'showTimeToFirstByte: $showTimeToFirstByte, '
      'enableTraceFetch: $enableTraceFetch, '
      'showFieldHints: $showFieldHints)';
}

/// Reads and writes the one settings key in the `sync` area.
final class SettingsStore {
  /// Binds the store to the sync storage facade.
  const SettingsStore(this._area);

  final StorageAreaApi _area;

  static const String _key = 'inga-settings';

  /// The stored settings, or [Settings.defaults] when nothing is stored.
  Future<Result<Settings, BrowserError>> read() async =>
      (await _area.read(_key)).map(Settings.decode);

  /// Writes [settings], replacing what was stored.
  Future<Result<void, BrowserError>> write(Settings settings) =>
      _area.write(_key, settings.encode());
}
