# Changelog

## [v1.0.3] - 2026-09-11
- Every Cloudflare field explains itself behind a `?` beside its label,
  the passive ones and the trace ones alike, and so does `alt-svc` in
  the header list: it is an offer of another route, not a measurement
  of the request that carried it. Off by default; the switch is in the
  settings.
- The trace row grew from five fields to nine: `kex`, `gateway`, `rbi`
  and the country of your address joined.

## [v1.0.2] - 2026-09-10
- Some improvements to the icons.
- Better hint when a proxy is in use.
- Firefox minimum version 140 (Android 142), which is what
  `data_collection_permissions` requires.

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
