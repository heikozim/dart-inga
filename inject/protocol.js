/* dart-inga (C) 2026 Heiko Zimmermann */
/* SPDX-License-Identifier: BSD-3-Clause */
/* Injected on popup open via scripting.executeScript (ADR-003): reads
   the page's negotiated protocol from its navigation entry. The
   completion value of the expression below travels back as the
   injection result. An empty string means "not measurable" (no
   navigation entry, or the browser withheld the field) and is never
   displayed. The value describes the LAST hop only. */
(() => {
  const entries = performance.getEntriesByType('navigation');
  return entries.length === 0 ? '' : entries[0].nextHopProtocol;
})();
