# Icon Fonts

Bundled icon font families, weight support, and how to register custom icon fonts.

## Overview

Woodcase ships six icon font families that cover the most popular open-source icon sets. The fonts are bundled as TTF files inside the library's resource bundle and are automatically registered with CoreText on first use — no setup required. When a `.pen` document contains an `icon` node, the renderer looks up the node's `icon` name within its `library` in the appropriate codepoint table, creates a Core Text glyph, and draws it where Pen places it in the node's box — by the font's metrics, not the glyph's ink (see *Where the glyph sits*).

Lucide, Feather and Phosphor match the font files the format's own editor ships. Material Symbols is a slightly newer build of the same Google Fonts files the editor downloads, drawn at the same axis settings (see *Material Symbols*), so its glyphs are the editor's too. What differences remain are Core Text's rasterization against the editor's, not mismatched font data.

## Supported Families

### Lucide

[Lucide](https://lucide.dev) is a community-maintained fork of Feather Icons with a significantly expanded icon set.

| | |
|---|---|
| **`.pen` family name** | `lucide` |
| **Bundled version** | `lucide-static@0.563.0` |
| **Icons** | ~1,668 |
| **Weight support** | Single weight |
| **License** | ISC |

### Feather

[Feather Icons](https://feathericons.com) is a collection of simply-designed open-source icons.

| | |
|---|---|
| **`.pen` family name** | `feather` |
| **Bundled version** | CDN-hosted `feather.ttf` (identical to the format's own editor) |
| **Icons** | ~287 |
| **Weight support** | Single weight |
| **License** | MIT |

> Note: The internal CTFont family name for Feather is `icomoon`, not `feather`. This is handled automatically by ``PenIconFontRegistry``.

### Phosphor

[Phosphor Icons](https://phosphoricons.com) is a flexible icon family with five weight variants packed into a single font file.

| | |
|---|---|
| **`.pen` family name** | `phosphor` |
| **Bundled version** | `@phosphor-icons@1.4.2` (v1) |
| **Base icons** | ~1,047 |
| **Total codepoints** | ~5,235 (1,047 × 5 weights) |
| **Weight variants** | regular, bold, fill, light, thin |
| **License** | MIT |

> Important: Woodcase bundles Phosphor **v1**, which packs all weight variants into a single font file with distinct codepoints per variant. Phosphor v2 (`@phosphor-icons/web`) splits weights into separate font files with different glyph outlines and is **not** compatible. The v1 font matches what the format's own editor bundles.

Phosphor weight variants are selected by appending a suffix to the icon name:

| Icon name | Weight |
|-----------|--------|
| `chat-dots` | Regular |
| `chat-dots-bold` | Bold |
| `chat-dots-fill` | Filled |
| `chat-dots-light` | Light |
| `chat-dots-thin` | Thin |

Each weight variant maps to a distinct Unicode codepoint within the same font file — no OpenType variation axes are involved.

### Material Symbols

[Material Symbols](https://fonts.google.com/icons) is Google's icon family, available in three visual styles that share the same codepoint mappings:

| | Outlined | Rounded | Sharp |
|---|---|---|---|
| **`.pen` family name** | `Material Symbols Outlined` | `Material Symbols Rounded` | `Material Symbols Sharp` |
| **Bundled version** | font version 2.926 | font version 2.926 | font version 2.926 |
| **Icons** | ~4,211 (shared) | ~4,211 (shared) | ~4,211 (shared) |
| **License** | Apache 2.0 | Apache 2.0 | Apache 2.0 |

All three variants are **variable fonts** with four axes — `FILL` (0–1), `GRAD` (−50–200), `opsz` (20–48) and `wght` (100–700). An icon node's `weight` sets `wght`; when the node sets none, Woodcase draws at **200**, as the format's own editor does. Every other axis stays at the font's default: unfilled, grade 0 and optical size 24, whatever the icon's size (see *Which cut of the glyph*).

#### Which cut of the glyph

The editor downloads Material Symbols from Google Fonts at run time (as of 2026-09, the `materialsymbols{outlined,rounded,sharp}` v290, v291 and v287 builds, font version 2.881). It draws an icon by setting its glyph at 14 pt with one variation, `wght` at the node's weight, and scaling the outline to the box. It never sets `opsz`, so every icon is drawn in the font's default 24 pt optical cut.

Core Text instead moves a variable font's `opsz` axis to the point size unless told not to. A 48 pt Material icon came out in the 48 pt cut, whose strokes are lighter and whose ink reaches further. With placement already right, Outlined `vpn_lock` scored 3.3 (24 × 24 at 2x), 4.7 (48 × 48) and 2.2 (64 × 32) MAE against Pen's export in the glyph's window. Drawn at optical size 24 it scores 0.65, 0.55 and 0.31, and Rounded and Sharp move the same way. The whole `icon-font-test` board went from 1.24 to 0.89 in the Core Graphics renderer and from 0.84 to 0.18 in the generated SwiftUI (`swift test -j 3 --filter "PenIconFontSnapshotTests|SwiftUIRenderTests"`). So the renderer, ``PenIconGlyph`` and the generated SwiftUI's `PenFonts` all turn automatic optical sizing off for an icon font (`kCTFontOpticalSizeAttribute: "none"`), as text already does (<doc:PenGoogleFonts>).

The font build is not the difference. Woodcase's 2.926 files and the editor's 2.881 files draw `vpn_lock`, `help`, `home`, `search` and `settings` with the same bounds at every axis setting probed, and the two builds score the same against Pen's export at optical size 24 (`xcrun swift scripts/icon-placement-fit.swift Tests/WoodcaseTests/Fixtures/render-icon-placement.pen --opsz 24`, then again with `--material-fonts <dir>` holding the editor's downloads; `--opsz auto` reproduces the old figures). Woodcase keeps the newer build. Its name table is a superset of the editor's: 4,211 names to 3,810, and every editor name resolves to the same glyph.

Kept on purpose: the editor's own name table lacks some names the font has, `expand_more` and `expand_less` among them, and draws its `help` placeholder for them. Woodcase resolves the real icon. Pen's behaviour is a gap in its table, not a rule of the format, so Woodcase does not copy it.

Material Symbols icons accept both hyphenated and underscored names — `vpn-lock` and `vpn_lock` both resolve correctly.

## How Icon Rendering Works

The rendering pipeline for an `icon` node:

1. **Resolve** — ``PenVariableResolver`` resolves any variable references in the icon's library name, icon name, weight, and fills.
2. **Layout** — ``PenLayoutEngine`` computes the icon's bounding rect. Icons default to `fitContent` sizing if no explicit width/height is set.
3. **Lookup** — ``PenIconFontRegistry`` maps the family and icon name to a Unicode codepoint and CTFont family name. The font is lazily registered with CoreText if this is the first use of that family.
4. **Render** — ``PenIconGlyph`` resolves the glyph (the library's placeholder for a name it does not know), creates its `CTFont` at the icon's size (the smaller of width and height) and places it by Pen's rule (below); `PenIconFontRenderer` sets it as a single-character line and draws it there, painted as text is (``PenGlyphPaint``). ``PenIconGlyph`` is public so that another renderer draws the same glyph at the same place rather than a copy of these rules; RapidPro's text rasterizer does.

For Material Symbols, step 4 applies the `wght` OpenType variation axis to the font descriptor before rendering, enabling continuous weight control, and turns Core Text's automatic optical sizing off so the glyph keeps the font's default 24 pt cut, as the editor draws it.

### Where the glyph sits

Pen places an icon's glyph by the **font's metrics, never by its ink**, and the renderer
and the generated SwiftUI (`PenIconShape`) follow the same rule:

- **Size.** The font size is the shorter side of the box.
- **Across.** The glyph's advance is centred across the box.
- **Down.** The line box is centred down the box. The line box is the font's ascent plus
  descent, **each rounded to a whole point at 14 pt** and then scaled to the icon's size.
  So the baseline sits at `height / 2 + size × (A − D) / 28`, where `A` and `D` are the
  ascent and descent at 14 pt, rounded.

For Lucide and Phosphor (ascent one em, descent zero) and Material Symbols (1.1 and 0.1
em) the baseline therefore lands on the bottom of an em square centred in the box. For
Feather (ascent 0.9375, descent 0.0625 em: 13.125 and 0.875 at 14 pt, which round to 13 and 1)
it lands at 13/14 of the em, 0.43 pt higher at 48 pt than unrounded metrics would put it.
A glyph whose ink is not centred in its em, such as Phosphor's `chat-dots-thin` or Material's
`vpn_lock`, therefore sits off-centre in its box, as it does in Pen.

The evidence is `Tests/WoodcaseTests/Fixtures/render-icon-placement.pen`: one artboard per
bundled library, each with two glyphs in 24 × 24, 48 × 48, 64 × 32 and 32 × 64 boxes, and
Pen's own 2x exports of it (`scripts/pen-oracle … --scale 2`, pen CLI 0.3.9, 2026-09-27).
`scripts/icon-placement-fit.swift` fits Pen's glyph origin in every box to a thirty-second
of a point by matching Core Text's rendering of the same outline against Pen's pixels.
Every fit lands within 0.08 pt of this rule, for all six families, at both sizes and in both
non-square boxes. A second probe with Feather's `chevron-down` and Lucide's `underline` at
16 to 128 pt put Feather's baseline at 0.9285 of the em at every size, so the offset scales
with the size and does not come from rounding at the drawn size. The fitted origins are
pinned in `PenIconPlacementTests`.

The 14 pt reference size is fitted, not read from Pen's source. Half-up rounding at 28 or
42 pt fits the six bundled fonts equally well, and 14 is Pen's default text size. A custom
icon font whose metrics round differently at those sizes would tell them apart. Centring the
advance and centring the em square cannot be told apart either, because every bundled glyph
probed has an advance of exactly one em.

Before this rule, both renderers centred the glyph's ink bounds. That put glyphs 0.5–2.9 pt
off Pen's (Phosphor `chat-dots-thin` at 48 pt was 2.9 pt high) and scored `icon-font-test`
5.25 MAE against Pen. With the rule it scores 1.24, and 0.89 once Material Symbols also keeps its default optical size (*Which cut of the glyph*).

### Unresolvable Icon Names

An `icon` node whose name is not in its library's table still renders — as that
library's own "unknown icon" glyph, the same substitution the format's own editor
performs, rather than nothing:

| `.pen` family | Placeholder icon |
|---|---|
| `lucide` | `circle-question-mark` |
| `feather` | `help-circle` |
| `phosphor` | `question` |
| `Material Symbols Outlined`/`Rounded`/`Sharp` | `help` |

``PenIconFontRegistry/placeholder(family:)`` resolves this glyph; it is deliberately
separate from ``PenIconFontRegistry/resolve(family:name:)``, so the `unknown-icon` lint
check (<doc:WoodcaseLint>), which detects an unresolvable name by that method
returning `nil`, still fires — the placeholder changes what renders, not what lints.
A family with no bundled placeholder, including a custom family registered via
``PenIconFontRegistry/register(family:fontName:mapping:)``, renders nothing for an
unresolvable name, as before.

## Registering Custom Icon Fonts

To use icon fonts beyond the six bundled families, register them with ``PenIconFontRegistry``:

```swift
// First, register the font file with Core Text (if not already installed), through
// PenFontRegistry so cached font resolutions learn the font set changed
let fontURL = Bundle.main.url(forResource: "MyIcons", withExtension: "ttf")!
PenFontRegistry.registerFont(at: fontURL)

// Then register the family with Woodcase
PenIconFontRegistry.shared.register(
    family: "my-icons",           // .pen family name used in the file
    fontName: "MyIcons",          // CTFont family name (as registered with CoreText)
    mapping: [                    // Icon name → Unicode codepoint
        "custom-star": 0xE001,
        "custom-heart": 0xE002,
    ]
)
```

After registration, any `icon` node with `library: "my-icons"` will render using your custom font.

## Looking Up Icon Names

`woodcase icons <library> [query]` lists a library's icon names — every one, sorted,
with no query, or the ones ranked nearest a query: an exact match, then a substring
match, then a fuzzy match on shared name tokens or a close edit distance.

```bash
woodcase icons lucide check
# check
# check-check
# check-line
# circle-check
# …
```

``IconNameMatcher`` is the ranking behind it, and the same one the `unknown-icon` lint
check (<doc:WoodcaseLint>) uses to propose a fix when an icon name is not in its
library's table — a Lucide rename like `check-circle-2` → `circle-check` finds its
replacement through the fuzzy tier, since the two names share no substring.

## Licensing

All bundled icon fonts are open-source and permit redistribution. Individual license files are included in the `LICENSES/` directory at the repository root:

| Family | License | File |
|--------|---------|------|
| Lucide | ISC | `LICENSES/lucide-LICENSE` |
| Feather | MIT | `LICENSES/feather-LICENSE` |
| Phosphor | MIT | `LICENSES/phosphor-LICENSE` |
| Material Symbols | Apache 2.0 | `LICENSES/material-symbols-LICENSE` |

## Topics

### Public API

- ``PenIconFontRegistry``
- ``PenIconFontRegistry/ResolvedIcon``
- ``IconNameMatcher``
