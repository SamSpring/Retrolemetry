# Design QA — graph headers and daily forecast temperatures

- Source visual truth: `codex-clipboard-58505b4f-3011-4e9b-afee-f84332200aa3.png` and `codex-clipboard-aea7a765-285d-4ded-a17b-ed91b49ba80d.png` (user-provided session attachments)
- Implementation screenshots: `Retrolemetry Screenshot 2026-08-17 at 16.46.07.jpeg` and `Retrolemetry Screenshot 2026-08-17 at 16.46.24.jpeg` (local QA captures)
- Comparison boards: `/tmp/retrolemetry-metrics-qa.png` and `/tmp/retrolemetry-weather-qa.png`
- Viewport: 960 × 540 points at native app capture density
- Source pixels: 1350 × 504 and 280 × 296
- Implementation pixels: 960 × 540 for both scenes
- Normalization: each source image was proportionally fitted or padded to a 960 × 540 comparison panel and placed beside the corresponding 960 × 540 implementation capture
- State: installed app, saved synthwave palette and saved typography/layout preferences, live System Metrics and settled Weather scenes

## Full-view comparison evidence

- System Metrics: each graph trace is confined to a canvas below a dedicated header band; no trace crosses the title or current-value text.
- Weather: all five daily low/high pairs render as full degree values rather than ellipses, with stronger size and weight than supporting forecast copy.

The supplied sources are focused failure captures, so the side-by-side boards use those focused regions beside the full 960 × 540 scene. Separate focused implementation crops were not needed because both corrected regions are clearly readable in the native captures.

## Required fidelity surfaces

- Fonts and typography: existing monospaced family, weights, and runtime scaling are preserved. Daily temperatures now use the primary type scale and remain untruncated.
- Spacing and layout rhythm: graph headers have a reserved vertical band and separator. Daily LOW, HIGH, and RAIN columns have explicit aligned widths.
- Colors and visual tokens: existing cyan/magenta synthwave tokens and contrast are unchanged.
- Image quality and asset fidelity: no raster assets are involved; the procedural vectors remain sharp at native resolution.
- Copy and content: labels, live readings, forecast conditions, and units are unchanged.

## Comparison history

1. Earlier P1: graph traces crossed the large graph title/value text. Fix: moved graph titles into a separate, intrinsic-height header above the clipped graph canvas. Post-fix evidence: `/tmp/retrolemetry-metrics-qa.png`.
2. Earlier P1: daily low/high temperatures collapsed to ellipses and were visually too small. Fix: gave LOW and HIGH dedicated 52-point columns and primary-scale 13-point bold type. Post-fix evidence: `/tmp/retrolemetry-weather-qa.png`.

## Findings

No actionable P0, P1, or P2 issues remain in the requested regions.

## Implementation checklist

- [x] Keep every full-metrics trace below its label/value header.
- [x] Preserve behavior under saved typography scaling.
- [x] Enlarge and align daily low/high temperatures.
- [x] Prevent daily temperatures from truncating.
- [x] Verify both settled live scenes in the installed app.

## Follow-up polish

No P3 follow-up is required for this change.

final result: passed
