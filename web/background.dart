// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Entry point of the background service worker: construct the wiring
/// and subscribe synchronously, so the event that woke the worker is
/// not lost. Everything with behaviour lives in `lib/worker.dart`,
/// where it is tested against the fake backend.
library;

import 'dart:js_interop';

import 'package:inga/worker.dart';
import 'package:web/web.dart';
import 'package:webext/browserkit_chrome.dart';
import 'package:webext/browserkit_firefox.dart';

/// Chosen at compile time: `dart compile js -Dfirefox=true` builds the
/// Firefox variant, the bare build stays Chrome. The constant is
/// compile-time, so dart2js tree-shakes the unused backend -- the
/// absence of the other backend is checked in every build.
const bool _firefox = bool.fromEnvironment('firefox');

/// Boots the worker, behind the safety net of [bootWorker]: a throw
/// out of construction or start goes out as a console.error instead of
/// the silent death of an unregistered worker (2026-09-02).
void main() {
  bootWorker(
    create: () => IngaWorker(
      backend: _firefox ? FirefoxBackend() : ChromeBackend(),
      log: (message) => console.error('inga: $message'.toJS),
    ),
    log: (message) => console.error('inga: $message'.toJS),
  );
}
