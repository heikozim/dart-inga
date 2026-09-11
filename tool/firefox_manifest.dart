// dart-inga -- Inga, a Manifest V3 header inspector
// Copyright (C) 2026 Heiko Zimmermann
// SPDX-License-Identifier: BSD-3-Clause

/// Derives the Firefox manifest from the ONE maintained source, the
/// Chrome `manifest.json` (decision of 2026-09-02: no second manifest
/// truth in the repository). Run by `tool/build_firefox.sh`:
///
///     dart run tool/firefox_manifest.dart <ausgabe-datei>
///
/// The transformation is mechanical and total -- everything not named
/// below is copied word for word, so name, version, description,
/// icons and permissions cannot drift:
///
/// - `background.service_worker` becomes `background.scripts` with the
///   same file: Firefox MV3 runs an event page, not a service worker.
/// - `browser_specific_settings.gecko.id` is added. The id below is
///   the ONLY place it lives (TEST-012: it exists for Firefox alone,
///   so this derivation is its home). It is public and permanent --
///   named by the project lead on 2026-09-02; changing it later makes
///   Firefox treat the extension as a different one.
/// - `browser_specific_settings.gecko.data_collection_permissions` is
///   added, declaring that nothing is collected. Mozilla requires the
///   key for every new extension; without it the AMO validator refuses
///   the package (measured 2026-09-03).
library;

import 'dart:convert';
import 'dart:io';

/// The permanent Firefox extension id (project lead, 2026-09-02).
const String geckoId = 'inga@heiko-zimmermann.com';

/// The oldest Firefox this build is declared for: the first version
/// supporting `data_collection_permissions` (desktop 140, Android 142
/// -- the minimum the AMO validator names for that key).
///
/// Without the key AMO derives a minimum from the manifest version
/// alone and lands on 109, where Manifest V3 arrived -- a number
/// nobody measured.
///
/// It was 128.0 until 2026-09-11, chosen as the ESR carrying the APIs
/// this extension uses. That reason has expired: ESR 128 went EOL on
/// 2025-09-16, and the current ESRs are 140 (until 2026-09-29) and 153
/// (since 2026-07-21), so 128 no longer shields a supported release --
/// it only made the AMO validator warn that
/// `data_collection_permissions` would be ignored on 128 to 139
/// (measured at the 1.0.2 upload: two warnings, desktop and Android).
const String minimaleFirefoxVersion = '140.0';

/// The same for Firefox for Android, where the key arrived two
/// releases later. Declared separately because `gecko_android`
/// inherits nothing from `gecko`.
const String minimaleAndroidVersion = '142.0';

/// Inga's data collection declaration: none.
///
/// `none` is Mozilla's value for "collects nothing" and is the only
/// entry allowed beside itself. It is the truthful one here: the
/// captured headers stay in `storage.session` inside the browser, the
/// settings stay in `storage.sync`, and the single outgoing request
/// (the opt-in trace fetch) goes to the inspected page's own origin --
/// there is no endpoint of ours anywhere in the extension.
const List<String> datenerhebung = <String>['none'];

void main(List<String> args) {
  final output = args.single;
  final manifest = jsonDecode(File('manifest.json').readAsStringSync())
      as Map<String, dynamic>;

  final background = manifest['background'] as Map<String, dynamic>;
  final worker = background.remove('service_worker') as String;
  background['scripts'] = <String>[worker];

  manifest['browser_specific_settings'] = <String, Object?>{
    'gecko': <String, Object?>{
      'id': geckoId,
      'strict_min_version': minimaleFirefoxVersion,
      'data_collection_permissions': <String, Object?>{
        'required': datenerhebung,
      },
    },
    'gecko_android': <String, Object?>{
      'strict_min_version': minimaleAndroidVersion,
    },
  };

  File(output).writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert(manifest)}\n',
  );
  stdout.writeln('geschrieben: $output (gecko.id $geckoId, '
      'strict_min_version $minimaleFirefoxVersion, '
      'gecko_android.strict_min_version $minimaleAndroidVersion, '
      'data_collection_permissions.required ${datenerhebung.join(', ')})');
}
