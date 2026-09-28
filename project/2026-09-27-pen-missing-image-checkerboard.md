# 2026-09-27 — Pen draws a checkerboard for an image it cannot load, not nothing

Leaf `46XAVC` (SwiftUI remote image fills, D4) asked what Pen shows for an image fill it cannot load, before
choosing what `AsyncImage`'s placeholder and failure states should draw. `PenSupport+Paint.swift`'s doc comment
on `Image(penResource:bundle:)` claimed "an empty image when it is not there, as Pen draws nothing for a missing
image" — that claim was never checked against Pen and is wrong; corrected in place alongside this doc.

## The probe

A minimal fixture, a 300×200 green frame containing a 260×160 rectangle whose fill is
`{"type": "image", "url": "./images/does-not-exist-46XAVC.png", "mode": "fill"}` — a relative path to a file
that does not exist:

```
scripts/pen-oracle <fixture>.pen --out <dir> --scale 1 --accept-invalid
```

(`--accept-invalid` because Pen reports the file "is not valid" for a missing image but still loads, draws and
exports it — the same shape as the malformed-mesh-point finding of 2026-09-26.) Pen version: the installed `pen`
CLI / Pen.app 1.2.14.

## What the export shows

The exported PNG is 300×200 RGBA, **fully opaque everywhere** (alpha 255 at every sampled point — this is not
transparency). Sampled with Pillow (`Image.getpixel`):

| Point | RGBA |
|---|---|
| (5, 5) — the green frame, outside the rectangle | (0, 255, 0, 255) |
| (30, 30), (150, 100) — inside the rectangle, one checker phase | (26, 255, 26, 255) |
| (150, 30), (30, 100), (270, 170) — inside the rectangle, the other phase | (0, 230, 0, 255) |

Both in-rectangle colours are the green frame colour with a translucent checker square blended over it: a white
square at roughly 10% opacity (0,255,0 → 26,255,26: solving `255×a = 26` gives `a ≈ 0.10`) and a black square at
roughly the same opacity (0,255,0 → 0,230,0: `255×(1−a) = 230` gives `a ≈ 0.10`). That is the classic
light/dark transparency-grid pattern, rendered as real opaque pixels — a placeholder Pen draws *over whatever is
behind the shape*, not a hole punched through it.

## Conclusion

Pen shows a visible checkerboard placeholder for an image fill it cannot load (a missing local file measured
here; a dead remote URL is a different failure path but there is no reason to expect Pen treats it differently
once the fetch fails). Woodcase's renderers do not reproduce this anywhere — the Core Graphics renderer, the
bundled-image SwiftUI path, and now the `AsyncImage` path all draw nothing (`Color.clear` or an empty `Image`)
for an unloadable image, and that gap is being kept on purpose (class b, per `project/2026-09-27-fidelity-gaps.md`'s
scheme) rather than built now: a checkerboard placeholder is a real feature (size, colours, pattern all
unverified beyond "roughly 10% opacity, alternating"), and no fixture in the repo currently measures against it.
If a future fidelity pass wants to close this gap, this probe fixture and its numbers are the starting evidence.
