// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// The background service worker's wiring: capture in, toolbar out.
///
/// Stateless on purpose. The capture lives in `storage.session` through
/// the library; every change signal re-derives the whole toolbar state
/// of the affected tab from storage. The worker can therefore die at any
/// moment (the Manifest V3 normal case) and the next event recomputes
/// everything -- there is no in-memory state worth losing.
///
/// Icon, badge and tooltip are set strictly per tab: the browser keeps
/// per-tab values while the tab lives and drops them when it closes, so
/// no `tabs.onActivated` listener and no polling is needed (decision of
/// 2026-09-01, following established practice).
library;

import 'dart:async';

import 'package:webext/browserkit.dart';
import 'package:webext/netkit.dart';

import 'presentation.dart';
import 'settings.dart';

/// Boots the worker behind a safety net (2026-09-02).
///
/// A throw out of construction or [IngaWorker.start] used to die
/// silently: the worker never registered, the extension showed a
/// permanently inactive worker with an empty error list and nothing to
/// debug -- an injected top-level throw reproduces exactly that
/// picture (PROOFS, sixth series). Reaching [log] here is the whole
/// point; rethrowing would only repeat the silent death. The entry
/// point calls this with the real backend; tests call it with a
/// throwing [create] and read the message.
void bootWorker({
  required IngaWorker Function() create,
  required void Function(String message) log,
}) {
  try {
    final worker = create();
    switch (worker.start()) {
      case Ok<void, BrowserError>():
        break; // Subscribed; there is nothing to report.
      case Err<void, BrowserError>(:final error):
        log('start failed: $error');
    }
  } on Object catch (thrown) {
    log('worker did not start: $thrown');
  }
}

/// Wires a [RequestCapture] to the toolbar.
final class IngaWorker {
  /// Builds the wiring over [backend].
  ///
  /// [log] receives one line per failure -- the paths here have no
  /// caller to return a `Result` to, so the report is the visible
  /// outcome (the library's `onError` contract). [toLocalTime] renders
  /// the tooltip's capture time; production uses the default, tests
  /// inject a fixed clock so expected strings are time zone free.
  IngaWorker({
    required Backend backend,
    required void Function(String message) log,
    DateTime Function(double epochMilliseconds) toLocalTime = _epochToLocalTime,
  })  : _action = ActionApi(backend),
        _settingsStore = SettingsStore(StorageApi(backend).sync),
        _log = log,
        _toLocalTime = toLocalTime {
    _capture = RequestCapture(
      backend: backend,
      onError: (error) => log('capture: $error'),
      // Refreshes are SERIALISED, never run side by side: a refresh
      // awaits several toolbar calls, and overlapping refreshes let a
      // stale presentation land its calls last and win. Measured in the
      // browser (proof runs of 2026-09-01): after a burst of events on
      // a freshly booted worker, a tab's toolbar stayed at the default
      // state while its capture was complete in storage.
      onTabChanged: (tabId) {
        _refreshWork = _refreshWork.then((_) => _refreshTab(tabId));
      },
    );
  }

  final ActionApi _action;
  final SettingsStore _settingsStore;
  final void Function(String message) _log;
  final DateTime Function(double epochMilliseconds) _toLocalTime;
  late final RequestCapture _capture;

  /// The refresh queue; see the onTabChanged wiring in the constructor.
  Future<void> _refreshWork = Future<void>.value();

  /// Subscribes the capture to the webRequest events.
  ///
  /// Call synchronously during worker start-up, or the event that woke
  /// the worker is lost (library contract on `RequestCapture.start`).
  ///
  /// Also queues one GLOBAL default-icon write (no tab id): the browser
  /// rasterises the manifest's `default_icon` once at extension load
  /// and caches it, so a changed icon file otherwise stays invisible on
  /// the toolbar until a browser restart -- observed 2026-09-01, when
  /// the beetle appeared as the options tab's favicon (read fresh from
  /// the file) while the toolbar kept the stale cached raster. Setting
  /// it through the action API reads the current files.
  Result<void, BrowserError> start() {
    final started = _capture.start();
    if (started.isOk) {
      _refreshWork = _refreshWork.then((_) => _applyGlobalDefaultIcon());
    }
    return started;
  }

  Future<void> _applyGlobalDefaultIcon() async {
    if (await _action.setIcon(iconPathsOf(IconState.none))
        case Err<void, BrowserError>(:final error)) {
      _log('global default icon: $error');
    }
  }

  /// The captured requests of [tabId] -- the popup's read path in tests.
  Future<Result<List<CapturedRequest>, BrowserError>> requestsForTab(
    int tabId,
  ) =>
      _capture.requestsForTab(tabId);

  /// Cancels the capture's subscriptions and finishes the pending
  /// refreshes; test teardown.
  Future<void> dispose() async {
    await _capture.dispose();
    await _refreshWork;
  }

  Future<void> _refreshTab(int tabId) async {
    // Read per refresh, so a settings change takes effect with the next
    // event -- no change listener, no immediate rewrite of open tabs
    // (decided 2026-09-01). A failed read is logged and falls back to
    // the defaults: a broken preference must not blank the toolbar.
    var settings = Settings.defaults;
    switch (await _settingsStore.read()) {
      case Ok<Settings, BrowserError>(:final value):
        settings = value;
      case Err<Settings, BrowserError>(:final error):
        _log('settings for tab $tabId: $error');
    }

    final read = await _capture.requestsForTab(tabId);
    switch (read) {
      case Ok<List<CapturedRequest>, BrowserError>(:final value):
        await _apply(
          tabId,
          TabPresentation.of(
            value,
            toLocalTime: _toLocalTime,
            showTimeToFirstByte: settings.showTimeToFirstByte,
          ),
        );
      case Err<List<CapturedRequest>, BrowserError>(:final error):
        _log('read of tab $tabId: $error');
    }
  }

  /// Sets the four toolbar values of one tab.
  ///
  /// Each call is checked on its own: a failed icon must not silence a
  /// working badge. The tooltip fallback is written as [extensionName]:
  /// a per-tab title cannot be cleared back to the manifest default
  /// (measured, see the constant's doc), so the fallback of
  /// specification section 4 is set explicitly.
  Future<void> _apply(int tabId, TabPresentation presentation) async {
    _check(
      'setIcon',
      tabId,
      await _action.setIcon(iconPathsOf(presentation.iconState), tabId: tabId),
    );
    _check(
      'setBadgeText',
      tabId,
      await _action.setBadgeText(presentation.badgeText, tabId: tabId),
    );
    final badgeColor = presentation.badgeColor;
    if (badgeColor != null) {
      _check(
        'setBadgeBackgroundColor',
        tabId,
        await _action.setBadgeBackgroundColor(badgeColor, tabId: tabId),
      );
    }
    _check(
      'setTitle',
      tabId,
      await _action.setTitle(
        presentation.tooltip ?? extensionName,
        tabId: tabId,
      ),
    );
  }

  void _check(String call, int tabId, Result<void, BrowserError> result) {
    if (result case Err<void, BrowserError>(:final error)) {
      // A tab that vanished between event and call is the expected
      // outcome of closing it (the TabGone contract; ordered
      // 2026-09-02) -- silence. Every other variant stays visible.
      if (error is TabGone) {
        return;
      }
      _log('$call for tab $tabId: $error');
    }
  }

  static DateTime _epochToLocalTime(double epochMilliseconds) =>
      DateTime.fromMillisecondsSinceEpoch(epochMilliseconds.round());
}
