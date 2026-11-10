# tla-visualize pitfalls

Each entry is a rule of SKILL.md (verbatim) and the run that taught it (ADR 0033).

### P1 — the container class

- Rule: A diagram container is `tv-pele`, never `pele`: pele's own SVG carries the class `pele`, and a rule on `.pele` lands on the SVG too.
- Case (2026-11-10, first CBRD-27967 page): the container rule `.pele{padding:22px;overflow-x:auto}` also padded every rendered SVG; a check that counted `.pele` elements found 22 hosts, 11 of them "empty" (the SVGs themselves).

### P2 — grid columns on a phone

- Rule: A grid column in the template is `minmax(0,1fr)`: a bare `1fr` grows to its widest diagram and widens the whole page on a phone.
- Case (2026-11-10): after diagrams got `min-width:640px` under 900px, the counterexample stage's one-column grid (`1fr`) grew to 710 px and the page scrolled sideways at 390 px.

### P3 — side gutters

- Rule: A section padding in the template sets top and bottom only: a `padding` shorthand on a `.tv-wrap` element erases its side gutters.
- Case (2026-11-10): `.tv-hero{padding:clamp(...) 0 64px}` on the `tv-wrap tv-hero` header set the side padding to 0; on a phone the headline touched the screen edge.

### P4 — fonts in nix

- Rule: A font comes into `tools/tla-visualize/tools.nix` as one pinned file: the google-fonts package fetches the whole google/fonts repository (gigabytes).
- Case (2026-11-10): `pkgs.google-fonts.override { fonts = [ "InterTight" ]; }` was still downloading the repository at 2.4 GB when it was stopped; Inter Tight now comes from one `fetchurl` of `ofl/intertight/InterTight[wght].ttf` at a pinned commit.

### P5 — screenshots of a section

- Rule: Verification scrolls with `window.scrollTo({top, behavior: 'instant'})` before a viewport screenshot: the page scrolls smoothly, and the screenshot tool's `selector` does not scroll.
- Case (2026-11-10): `scrollIntoView()` returned `scrollY = 0` and the `selector` screenshot of `#compare` showed the hero.
