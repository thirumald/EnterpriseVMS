# Media

Real footage and photos are plain files here, picked up at runtime — no code change needed.

**Video** — put clips in `video/` and list them in `manifest.json`:

```json
{ "clips": [
  { "src": "media/video/street-1.mp4", "poster": "media/video/street-1.jpg", "title": "Street", "credit": "Author / Source / Licence" }
] }
```

Each camera is assigned a clip deterministically and starts at a different offset. MP4 (H.264) plays everywhere; add WebM if you need it.
The bundled clips are **generated samples** (procedurally rendered, labelled in-frame), not real footage; replace them with real clips. Optional `webm` is a fallback source. Keep clips short (10–30 s, ≤ 8 MB, 720p) so the GitHub Pages site stays fast. With an empty manifest the tiles fall back to a labelled **SIMULATED** canvas feed.

**Photos** — `sites/<site-id>.jpg` (`portgate`, `airport`, `metro`, `refinery`, `toll`, `hq`), roughly 480×330.

Use only footage you have the right to redistribute (your own, or CC0 / Pexels / Pixabay-style licences) and record the credit in `manifest.json`.
Publicly redistributing footage of identifiable people or private premises can have legal and privacy implications.
