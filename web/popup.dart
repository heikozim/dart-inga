// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The popup: renders what `lib/popup_model.dart` decides.
///
/// This file is the DOM seam and holds no view logic of its own. Header
/// values are attacker controlled and are written exclusively through
/// `textContent` -- never as markup (specification section 7).
///
/// The capture is read STRAIGHT from `storage.session`: a
/// `RequestCapture` that is never started shares the store the worker
/// writes, and the data outlives the worker by design, so the popup
/// neither wakes the worker nor needs a message protocol.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:inga/external_checks.dart';
import 'package:inga/popup_model.dart';
import 'package:inga/settings.dart';
import 'package:inga/trace.dart';
import 'package:web/web.dart';
import 'package:webext/browserkit.dart';
import 'package:webext/browserkit_chrome.dart';
import 'package:webext/browserkit_firefox.dart';
import 'package:webext/netkit.dart';

/// Chosen at compile time: `dart compile js -Dfirefox=true` builds the
/// Firefox variant, the bare build stays Chrome. The constant is
/// compile-time, so dart2js tree-shakes the unused backend -- the
/// absence of the other backend is checked in every build.
const bool _firefox = bool.fromEnvironment('firefox');

final Backend _backend = _firefox ? FirefoxBackend() : ChromeBackend();
final SettingsStore _settingsStore = SettingsStore(StorageApi(_backend).sync);
final RuntimeApi _runtime = RuntimeApi(_backend);
late final RequestCapture _capture;

/// The mutable view state; every render derives the view from it anew.
List<CapturedRequest> _requests = const <CapturedRequest>[];

/// The page's negotiated protocol, read once on popup open by injecting
/// `inject/protocol.js` into the active tab (ADR-003) -- the first and
/// only touch of a foreign page. Null when the tab cannot be injected
/// (chrome pages, the store) or the entry reports an empty string:
/// "not measurable", shown as nothing.
String? _pageProtocol;
int _selectedIndex = 0;
bool _showResponseHeaders = true;
Settings _settings = Settings.defaults;

HTMLSelectElement get _requestSelect =>
    document.getElementById('requests')! as HTMLSelectElement;
HTMLSelectElement get _themeSelect =>
    document.getElementById('theme')! as HTMLSelectElement;
HTMLInputElement get _filterInput =>
    document.getElementById('filter')! as HTMLInputElement;
HTMLElement get _headersContainer =>
    document.getElementById('headers')! as HTMLElement;
HTMLElement get _cloudflareLine =>
    document.getElementById('cloudflare')! as HTMLElement;
HTMLElement get _statusBadge =>
    document.getElementById('status')! as HTMLElement;
HTMLElement get _countLabel => document.getElementById('count')! as HTMLElement;
HTMLElement get _messageLine =>
    document.getElementById('message')! as HTMLElement;
HTMLButtonElement get _requestSideButton =>
    document.getElementById('show-request')! as HTMLButtonElement;
HTMLButtonElement get _responseSideButton =>
    document.getElementById('show-response')! as HTMLButtonElement;
HTMLButtonElement get _externalButton =>
    document.getElementById('external')! as HTMLButtonElement;
HTMLElement get _externalMenu =>
    document.getElementById('external-menu')! as HTMLElement;
HTMLElement get _copyUrlButton =>
    document.getElementById('copy-url')! as HTMLElement;
HTMLElement get _selectorRow =>
    document.querySelector('.selector-row')! as HTMLElement;

/// Loads settings and capture, wires the controls, renders.
Future<void> main() async {
  _capture = RequestCapture(
    backend: _backend,
    onError: (error) => _showMessage('storage: $error'),
  );
  _wireControls();

  switch (await _settingsStore.read()) {
    case Ok<Settings, BrowserError>(:final value):
      _settings = value;
    case Err<Settings, BrowserError>(:final error):
      _showMessage('settings: $error');
  }
  _applyTheme();

  final tabId = await _activeTabId();
  if (tabId != null) {
    switch (await _capture.requestsForTab(tabId)) {
      case Ok<List<CapturedRequest>, BrowserError>(:final value):
        _requests = selectorOrder(value);
      case Err<List<CapturedRequest>, BrowserError>(:final error):
        _showMessage('capture: $error');
    }
    switch (await ScriptingApi(_backend).executeScriptFilesForString(
      tabId: tabId,
      files: const ['inject/protocol.js'],
    )) {
      case Ok<String?, BrowserError>(:final value):
        _pageProtocol = value != null && value.isNotEmpty ? value : null;
      case Err<String?, BrowserError>():
        // Pages the browser refuses to inject into (chrome://, the web
        // store) simply have no protocol row; that is a property of the
        // page, not an error worth a message line.
        break;
    }
  }
  _render();
}

/// The active tab of the current window, without the `tabs` permission:
/// the id is available, address and title deliberately are not.
Future<int?> _activeTabId() async {
  final queried = await TabsApi(_backend)
      .query(const TabQuery(isActive: true, isInCurrentWindow: true));
  switch (queried) {
    case Ok<List<TabInfo>, BrowserError>(:final value):
      for (final tab in value) {
        if (tab.id != null) {
          return tab.id;
        }
      }
      _showMessage('no active tab');
      return null;
    case Err<List<TabInfo>, BrowserError>(:final error):
      _showMessage('tabs: $error');
      return null;
  }
}

void _wireControls() {
  _requestSelect.onChange.listen((_) {
    _selectedIndex = _requestSelect.selectedIndex;
    _render();
  });
  _requestSideButton.onClick.listen((_) {
    _showResponseHeaders = false;
    _render();
  });
  _responseSideButton.onClick.listen((_) {
    _showResponseHeaders = true;
    _render();
  });
  _filterInput.onInput.listen((_) => _render());
  _themeSelect.onChange.listen((_) => unawaited(_themeChanged()));
  document.getElementById('options')!.onClick.listen(
        (_) => unawaited(_openOptions()),
      );
  document.getElementById('copy')!.onClick.listen(
        (_) => unawaited(_copyView()),
      );
  // The selector shows the address truncated to its width; this copies
  // it whole. It is its own control beside the selector, so opening the
  // list and copying never share a click.
  _copyUrlButton.onClick.listen((_) => unawaited(_copySelectedUrl()));
  // The external-tools menu (ADR-002): the button toggles, a click on
  // an entry opens the tool and closes, any click elsewhere closes.
  _externalButton.onClick.listen((event) {
    event.stopPropagation();
    _toggleExternalMenu();
  });
  _externalMenu.onClick.listen((event) => event.stopPropagation());
  document.body!.onClick.listen((_) => _externalMenu.hidden = true.toJS);
}

void _toggleExternalMenu() {
  final menu = _externalMenu;
  if (!menu.hasAttribute('hidden')) {
    menu.hidden = true.toJS;
    return;
  }
  final host = checkHostOf(_requests);
  if (host == null) {
    return;
  }
  menu.textContent = '';
  final hostLine = document.createElement('div') as HTMLElement;
  hostLine.className = 'ext-host';
  hostLine.textContent = host;
  menu.append(hostLine);
  for (final check in externalChecks(host)) {
    final item = document.createElement('button') as HTMLButtonElement;
    item.className = 'ext-item';
    item.textContent = check.name;
    item.onClick.listen((_) {
      // Inga fetches nothing: the tool loads in its own new tab.
      window.open(check.url, '_blank', 'noopener');
      _externalMenu.hidden = true.toJS;
    });
    menu.append(item);
  }
  menu.hidden = false.toJS;
}

Future<void> _themeChanged() async {
  final theme = ThemeSetting.values.asNameMap()[_themeSelect.value] ??
      ThemeSetting.system;
  _settings = _settings.copyWith(theme: theme);
  _applyTheme();
  if (await _settingsStore.write(_settings)
      case Err<void, BrowserError>(:final error)) {
    _showMessage('settings: $error');
  }
}

Future<void> _openOptions() async {
  if (await _runtime.openOptionsPage()
      case Err<void, BrowserError>(:final error)) {
    _showMessage('options: $error');
  }
}

Future<void> _copyView() async {
  final request = _selectedRequest();
  if (request == null) {
    return;
  }
  final text = copyText(
    request,
    _currentSections(request),
    toLocalTime: _toLocalTime,
  );
  if (await _writeClipboard(text)) {
    _flashCopied(document.getElementById('copy')! as HTMLElement);
  }
}

Future<void> _copySelectedUrl() async {
  final request = _selectedRequest();
  if (request == null) {
    return;
  }
  if (await _writeClipboard(request.finalUrl)) {
    // The receipt goes on the row, so it can sit beside the button
    // instead of covering the symbol.
    _flashCopied(_selectorRow);
  }
}

Future<bool> _writeClipboard(String text) async {
  try {
    await window.navigator.clipboard.writeText(text).toDart;
    return true;
  } on Object catch (error) {
    _showMessage('copy failed: $error');
    return false;
  }
}

void _flashCopied(HTMLElement element) {
  element.classList.add('copied');
  Timer(const Duration(milliseconds: 1200), () {
    element.classList.remove('copied');
  });
}

CapturedRequest? _selectedRequest() {
  if (_requests.isEmpty) {
    return null;
  }
  final index = _selectedIndex.clamp(0, _requests.length - 1);
  return _requests[index];
}

List<HeaderSection> _currentSections(CapturedRequest request) => sectionsOf(
      request,
      showResponseHeaders: _showResponseHeaders,
      filter: _filterInput.value,
      settings: _settings,
    );

void _render() {
  _renderSelector();
  _requestSideButton.classList.toggle('active', !_showResponseHeaders);
  _responseSideButton.classList.toggle('active', _showResponseHeaders);
  // The external-tools button follows the page: enabled only when the
  // main document has an http(s) host; the menu never survives a
  // rerender with possibly different requests.
  _externalButton.disabled = checkHostOf(_requests) == null;
  _externalMenu.hidden = true.toJS;

  final request = _selectedRequest();
  _renderCloudflareLine(request);
  final container = _headersContainer;
  container.textContent = '';
  if (request == null) {
    _statusBadge.hidden = true.toJS;
    _countLabel.textContent = 'nothing captured for this tab';
    return;
  }

  final status = request.finalStatusCode;
  _statusBadge.hidden = false.toJS;
  _statusBadge.textContent = status == null ? 'pending' : '$status';
  _statusBadge.className = 'status ${statusClass(status)}';

  final sections = _currentSections(request);
  _countLabel.textContent = '${headerCount(sections)} headers';
  for (final section in sections) {
    if (section.hopLabel != null) {
      final hopLine = document.createElement('div') as HTMLElement;
      hopLine.className = 'hop';
      hopLine.textContent = section.hopLabel;
      container.append(hopLine);
    }
    for (final header in section.headers) {
      final row = document.createElement('div') as HTMLElement;
      row.className = 'kv-row';
      final name = document.createElement('span') as HTMLElement;
      name.className = 'kv-label';
      name.textContent = header.name;
      final value = document.createElement('span') as HTMLElement;
      value.className = 'kv-value';
      value.textContent = header.value;
      row
        ..append(name)
        ..append(value);
      row.onClick.listen((_) => unawaited(_copyRow(row, header)));
      container.append(row);
    }
  }
}

/// The Cloudflare line under the selector: a colour dot with the
/// signal word, then the fields as rows of the shared label/value
/// table (unified with the header list 2026-09-03) -- all through
/// textContent.
void _renderCloudflareLine(CapturedRequest? request) {
  final line = _cloudflareLine;
  line.textContent = '';
  if (request == null) {
    line.hidden = true.toJS;
    return;
  }
  line.hidden = false.toJS;

  final model = cloudflareLineOf(request, pageProtocol: _pageProtocol);
  final signalRow = document.createElement('div') as HTMLElement;
  signalRow.className = 'cf-row';
  final signal = document.createElement('span') as HTMLElement;
  signal.className = 'cf-signal';
  final dot = document.createElement('span') as HTMLElement;
  dot.className = switch (model.badge) {
    CloudflareLineBadge.cloudflare => 'cf-dot cf-yes',
    CloudflareLineBadge.notCloudflare => 'cf-dot cf-no',
    CloudflareLineBadge.pending => 'cf-dot cf-pending',
  };
  final word = document.createElement('span') as HTMLElement;
  word.className = 'cf-word';
  word.textContent = switch (model.badge) {
    CloudflareLineBadge.cloudflare => 'cloudflare',
    CloudflareLineBadge.notCloudflare => 'not cloudflare',
    CloudflareLineBadge.pending => 'pending',
  };
  signal
    ..append(dot)
    ..append(word);
  if (model.badge == CloudflareLineBadge.cloudflare) {
    if (_settings.enableTraceFetch) {
      // The one outgoing request, click-only and opt-in (ADR-001).
      word.classList.add('cf-word-clickable');
      word.title = 'Fetch /cdn-cgi/trace from this origin';
      word.onClick.listen((_) => unawaited(_fetchTrace(request, line)));
    } else {
      // Off is the default, and in that state the word still reads like
      // something one could click. The note is VISIBLE, not only a
      // tooltip: a native tooltip needs the reader to suspect there is
      // something to hover over, and in a popup window it may not be
      // drawn at all. The full sentence stays on the title for whoever
      // does hover.
      const grund = 'Trace fetch is off. Turn it on in the settings '
          '(the gear) to fetch /cdn-cgi/trace from this origin.';
      word.title = grund;
      final hinweis = document.createElement('span') as HTMLElement;
      hinweis.className = 'cf-off';
      hinweis.textContent = 'trace off';
      hinweis.title = grund;
      signal.append(hinweis);
    }
  }
  signalRow.append(signal);
  line.append(signalRow);

  if (model.fields.isNotEmpty) {
    final fields = document.createElement('div') as HTMLElement;
    fields.className = 'cf-fields';
    for (final field in model.fields) {
      fields.append(_cloudflareFieldRow(field));
    }
    line.append(fields);
  }
}

/// Fires the one outgoing request of ADR-001 and renders its answer
/// into the trace row -- values of the TRACE request, marked as such.
Future<void> _fetchTrace(CapturedRequest request, HTMLElement line) async {
  final row = _ensureTraceRow(line);
  final url = traceUrlFor(request.finalUrl);
  if (url == null) {
    _fillTraceRow(row, error: 'failed \u2014 no http origin');
    return;
  }
  _fillTraceRow(row, note: 'fetching \u2026');
  try {
    final controller = AbortController();
    final response = await window
        .fetch(url.toJS, RequestInit(signal: controller.signal))
        .toDart
        .timeout(const Duration(seconds: 10), onTimeout: () {
      controller.abort();
      throw TimeoutException('trace', const Duration(seconds: 10));
    });
    if (!response.ok) {
      _fillTraceRow(row, error: 'failed \u2014 HTTP ${response.status}');
      return;
    }
    final body = (await response.text().toDart).toDart;
    final fields = traceFields(body);
    if (fields.isEmpty) {
      _fillTraceRow(row, error: 'failed \u2014 unexpected answer');
      return;
    }
    _fillTraceRow(row, fields: fields);
  } on TimeoutException {
    _fillTraceRow(row, error: 'failed \u2014 timeout (10 s)');
  } on Object {
    _fillTraceRow(row, error: 'failed \u2014 network error');
  }
}

HTMLElement _ensureTraceRow(HTMLElement line) {
  final existing = line.querySelector('.cf-trace');
  if (existing != null) {
    return existing as HTMLElement;
  }
  final row = document.createElement('div') as HTMLElement;
  row.className = 'cf-trace';
  line.append(row);
  return row;
}

void _fillTraceRow(
  HTMLElement row, {
  List<CloudflareField>? fields,
  String? note,
  String? error,
}) {
  row.textContent = '';
  if (fields != null) {
    // No disclosure (ordered 2026-09-01): the answer joins the SAME
    // table as the passive part, beneath a section heading that marks
    // the values as describing the trace request. The note/error row
    // above is cleared; a repeated click replaces the previous answer.
    row.remove();
    final line = _cloudflareLine;
    var table = line.querySelector('.cf-fields') as HTMLElement?;
    if (table == null) {
      table = document.createElement('div') as HTMLElement;
      table.className = 'cf-fields';
      line.append(table);
    }
    while (true) {
      final part = table.querySelector('.cf-trace-part');
      if (part == null) {
        break;
      }
      part.remove();
    }
    final divider = document.createElement('div') as HTMLElement;
    divider.className = 'hop cf-trace-part';
    divider.textContent = 'trace request';
    divider.title = 'These values describe the trace request, not the page';
    table.append(divider);
    for (final field in fields) {
      final fieldRow = _cloudflareFieldRow(field);
      fieldRow.classList.add('cf-trace-part');
      table.append(fieldRow);
    }
    return;
  }

  final tag = document.createElement('span') as HTMLElement;
  tag.className = 'cf-trace-tag';
  tag.textContent = 'trace request: ';
  row.append(tag);
  final span = document.createElement('span') as HTMLElement;
  span.className = error != null ? 'cf-trace-error' : 'cf-trace-tag';
  span.textContent = error ?? note ?? '';
  row.append(span);
}

HTMLElement _cloudflareFieldRow(CloudflareField field) {
  final row = document.createElement('div') as HTMLElement;
  row.className = 'kv-row';
  // A click copies the field like a header row does, receipt included
  // (requested 2026-09-01).
  row.onClick.listen((_) => unawaited(_copyCloudflareField(row, field)));
  final label = field.label;
  if (label != null) {
    final labelSpan = document.createElement('span') as HTMLElement;
    labelSpan.className = 'kv-label';
    labelSpan.textContent = label;
    row.append(labelSpan);
  }
  // A value without a label (local address, no answer yet) fills the
  // whole row; with a label it sits in the shared value column.
  final valueSpan = document.createElement('span') as HTMLElement;
  valueSpan.className = 'kv-value';
  valueSpan.textContent = field.value;
  row.append(valueSpan);
  return row;
}

Future<void> _copyCloudflareField(
  HTMLElement row,
  CloudflareField field,
) async {
  if (await _writeClipboard(cloudflareFieldLine(field))) {
    _flashCopied(row);
  }
}

Future<void> _copyRow(HTMLElement row, HttpHeader header) async {
  if (await _writeClipboard(headerLine(header))) {
    _flashCopied(row);
  }
}

void _renderSelector() {
  final select = _requestSelect;
  select.textContent = '';
  for (final request in _requests) {
    final option = document.createElement('option') as HTMLOptionElement;
    option.textContent = requestLabel(request);
    select.append(option);
  }
  if (_requests.isNotEmpty) {
    select.selectedIndex = _selectedIndex.clamp(0, _requests.length - 1);
  }
}

void _applyTheme() {
  document.documentElement!.setAttribute('data-theme', _settings.theme.name);
  _themeSelect.value = _settings.theme.name;
}

void _showMessage(String message) {
  final line = _messageLine;
  line.textContent = message;
  line.hidden = false.toJS;
}

DateTime _toLocalTime(double epochMilliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(epochMilliseconds.round());
