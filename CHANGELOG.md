# Changelog

## [v1.0.1] - 2026-09-03
- Toolbar icon: red when the site is not behind Cloudflare, orange when
  it is, grey while nothing was captured. The 1.0.0 package still
  carried the earlier icons.

## [v1.0.0] - 2026-09-03
- First release: HTTP headers, Cloudflare detection and time to first
  byte, for Chrome and Firefox.
- Nothing leaves the browser on its own. The trace fetch and the
  external checks are off by default and need a click.

## [v0.1.0] - 2026-09-02
- First working version: capture, popup, toolbar states, options.
