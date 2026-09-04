# dart-inga

Inga (Inspect Network, Gateways, Addresses) is a Manifest V3 browser
extension, written in Dart, that inspects the HTTP response headers
of the page in the active tab. The toolbar badge shows the time to
first byte, the icon color shows whether the page was served through
Cloudflare, and the popup lists the captured headers.

Inga reads what the browser loads anyway (webRequest); nothing leaves
the browser on its own, and nothing is stored beyond the session.
Exactly two actions hand the inspected page's hostname to a third
party, both only on an explicit click:

- the trace fetch: one GET to `/cdn-cgi/trace` at the origin of the
  inspected page -- no path, no query beyond that -- behind a setting
  that is off by default;
- the check menu: a click opens an external check tool (SSL Labs,
  Mozilla Observatory, ...) in a new tab; the menu shows the hostname
  before the click.

Header values are rendered as text, never as markup.

## Building from source

This is the point of this repository: the extension requests
`<all_urls>`, so the shipped compilate should be reproducible from
source. Dart SDK >= 3.5 (built with 3.13.2).

    dart pub get
    tool/build.sh           # Chrome build: build/*.js
    tool/build_firefox.sh   # Firefox variant: build-firefox/ext/
    tool/package.sh         # store zip: dist/

Chrome loads the repository root as an unpacked extension; Firefox
loads `build-firefox/ext` temporarily (about:debugging). The Firefox
manifest is generated from the one maintained `manifest.json` by
`tool/firefox_manifest.dart`. The library dependency (`webext`) is
pinned to a git tag in `pubspec.yaml`.

## What was measured

Capture and rendering were proven in a real browser, and every build
is checked for the tree-shaking of the backend it does not use. Those
measurements are kept with the development repository, not here.

## Development

Development happens in a private repository; this public repository
carries the tagged release states.

## License

BSD-3-Clause; the full text is in `LICENSE`.

The compiled JavaScript embeds code from third-party packages: the
Chrome build embeds `chrome_extension` (BSD-2-Clause, (c) 2023 The
chrome_extension.dart project authors); both builds embed
`package:web` (BSD-3-Clause) and the Dart SDK runtime emitted by
dart2js (BSD-3-Clause, the Dart project authors). Their license
texts ship with the packaged extension (`THIRD-PARTY-NOTICES`).

Copyright (C) 2026 Heiko Zimmermann <addon@heiko-zimmermann.com>
