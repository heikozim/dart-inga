// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The options page: the three settings of specification section 8,
/// stored on change. One storage key, two places operating it -- the
/// theme switch in the popup header is the other one; each page reads
/// on open.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:inga/about.dart';
import 'package:inga/settings.dart';
import 'package:web/web.dart';
import 'package:webext/browserkit.dart';
import 'package:webext/browserkit_chrome.dart';
import 'package:webext/browserkit_firefox.dart';

/// Chosen at compile time: `dart compile js -Dfirefox=true` builds the
/// Firefox variant, the bare build stays Chrome. The constant is
/// compile-time, so dart2js tree-shakes the unused backend -- the
/// absence of the other backend is checked in every build.
const bool _firefox = bool.fromEnvironment('firefox');

final Backend _backend = _firefox ? FirefoxBackend() : ChromeBackend();
final SettingsStore _store = SettingsStore(StorageApi(_backend).sync);
Settings _settings = Settings.defaults;

HTMLSelectElement get _themeSelect =>
    document.getElementById('theme')! as HTMLSelectElement;
HTMLInputElement get _showTtfbBox =>
    document.getElementById('show-ttfb')! as HTMLInputElement;
HTMLInputElement get _traceBox =>
    document.getElementById('trace')! as HTMLInputElement;
HTMLInputElement get _collapseBox =>
    document.getElementById('collapse')! as HTMLInputElement;
HTMLInputElement get _sortBox =>
    document.getElementById('sort')! as HTMLInputElement;
HTMLElement get _messageLine =>
    document.getElementById('message')! as HTMLElement;

/// Loads the settings, fills the controls, saves on every change.
Future<void> main() async {
  switch (await _store.read()) {
    case Ok<Settings, BrowserError>(:final value):
      _settings = value;
    case Err<Settings, BrowserError>(:final error):
      _showMessage('settings: $error');
  }
  _applyToControls();

  _themeSelect.onChange.listen((_) {
    final theme = ThemeSetting.values.asNameMap()[_themeSelect.value] ??
        ThemeSetting.system;
    unawaited(_save(_settings.copyWith(theme: theme)));
  });
  _showTtfbBox.onChange.listen((_) {
    unawaited(
      _save(_settings.copyWith(showTimeToFirstByte: _showTtfbBox.checked)),
    );
  });
  _traceBox.onChange.listen((_) {
    unawaited(
      _save(_settings.copyWith(enableTraceFetch: _traceBox.checked)),
    );
  });
  _collapseBox.onChange.listen((_) {
    unawaited(
      _save(_settings.copyWith(collapseRepeatedHeaders: _collapseBox.checked)),
    );
  });
  _sortBox.onChange.listen((_) {
    unawaited(
      _save(_settings.copyWith(sortHeadersAlphabetically: _sortBox.checked)),
    );
  });

  await _showVersion();
}

/// Reads the version from the packaged manifest -- one source, never a
/// second bookkeeping place. Fetching the extension's own
/// `manifest.json` is package-internal, not an outgoing request.
Future<void> _showVersion() async {
  final String url;
  switch (RuntimeApi(_backend).urlForPath('manifest.json')) {
    case Ok<String, BrowserError>(:final value):
      url = value;
    case Err<String, BrowserError>(:final error):
      _showMessage('version: $error');
      return;
  }
  final String manifestJson;
  try {
    final response = await window.fetch(url.toJS).toDart;
    manifestJson = (await response.text().toDart).toDart;
  } on Object catch (error) {
    _showMessage('version: $error');
    return;
  }
  final version = versionFromManifestJson(manifestJson);
  if (version == null) {
    _showMessage('version: manifest.json carries no readable version');
    return;
  }
  document.getElementById('version')!.textContent = 'Inga $version \u00b7 ';
}

Future<void> _save(Settings changed) async {
  _settings = changed;
  _applyToControls();
  if (await _store.write(changed) case Err<void, BrowserError>(:final error)) {
    _showMessage('settings: $error');
  }
}

void _applyToControls() {
  _themeSelect.value = _settings.theme.name;
  _showTtfbBox.checked = _settings.showTimeToFirstByte;
  _traceBox.checked = _settings.enableTraceFetch;
  _collapseBox.checked = _settings.collapseRepeatedHeaders;
  _sortBox.checked = _settings.sortHeadersAlphabetically;
  document.documentElement!.setAttribute('data-theme', _settings.theme.name);
}

void _showMessage(String message) {
  final line = _messageLine;
  line.textContent = message;
  line.hidden = false.toJS;
}
