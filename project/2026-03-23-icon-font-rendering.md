# Plan: Icon Font Rendering

## Context

The woodcase-app fixture uses Lucide icons throughout (bell, heart, star, house, book-open, plus, sliders-horizontal), but `icon_font` nodes are currently skipped during rendering. Pencil supports 6 icon font families: lucide, feather, Material Symbols Outlined/Rounded/Sharp, and phosphor. We want icon rendering to be first-class — fonts and codepoint mappings ship with the library so .pen files "just work."

## Font Inventory

| Family | Files | Size (approx) | Weight support | License |
|--------|-------|---------------|----------------|---------|
| lucide | `lucide.ttf` | 810KB | Single | ISC |
| feather | `feather.ttf` | ~200KB | Single | MIT |
| phosphor | `phosphor.ttf` (regular) | ~500KB | Single (other styles are separate families) | MIT |
| Material Symbols Outlined | `MaterialSymbolsOutlined.ttf` | ~2-3MB | Variable (`wght` 100-700) | Apache 2.0 |
| Material Symbols Rounded | `MaterialSymbolsRounded.ttf` | ~2-3MB | Variable (`wght` 100-700) | Apache 2.0 |
| Material Symbols Sharp | `MaterialSymbolsSharp.ttf` | ~2-3MB | Variable (`wght` 100-700) | Apache 2.0 |

Total: ~8-10MB. All licenses permit redistribution with attribution.

## Architecture

- **Font files bundled in library target** via `.copy("IconFonts/Fonts")` in Package.swift — users get icons out of the box
- **Auto-registration**: `PenIconFontRegistry` lazily registers bundled fonts with `CTFontManagerRegisterFontsForURL(.process)` on first render
- **Compiled-in Swift dictionaries** for codepoint mappings (no JSON resource loading)
- **Dedicated `PenIconFontRenderer`** — single-glyph CoreText rendering, separate from `PenTextRenderer`
- **`PenIconFontRegistry`** — maps family name → icon name → Unicode codepoint. Ships with all 6 families; users can register additional families via `register(family:mapping:)`
- **Variable weight support** for Material Symbols via CTFontDescriptor OpenType variation attributes (`wght` axis)
- **Silent skip** for unknown icons or unavailable fonts
- **License attribution** in a `LICENSES/` directory or dedicated section

## Steps

### 1. Download and bundle all icon fonts
- Download TTFs for all 6 families (lucide already in Tests/Fonts, move to Sources)
- Place in `Sources/Woodcase/IconFonts/Fonts/`
- Add `.copy("IconFonts/Fonts")` to library target resources in Package.swift
- Collect license files into `LICENSES/` and update README attribution

### 2. Add `width`/`height`/`effects`/`blendMode` to `IconFontData`
- `Sources/Woodcase/Models/PenNode.swift` — add properties, update init + CodingKeys
- `Sources/Woodcase/PenVariableResolver.swift` — resolve new properties in `resolveIconFontData`
- Red test: parse an icon_font node with width/height, assert values present

### 3. Fix layout engine for icon_font sizing
- `Sources/Woodcase/PenLayoutEngine.swift` — add `.iconFont(d)` case to `extractLeafWidth`/`extractLeafHeight`
- Red test: layout an icon_font with fixed dimensions, assert rect matches

### 4. Create `PenIconFontRegistry` with auto-registration
- New: `Sources/Woodcase/IconFonts/PenIconFontRegistry.swift`
- Thread-safe via `OSAllocatedUnfairLock`
- `codepoint(family:name:) -> UInt32?` — looks up codepoint, auto-registers built-in fonts on first call
- `register(family:mapping:)` — for user-provided icon fonts
- Font file registration: locates bundled TTFs via `Bundle.module` and registers with CoreText
- Red tests: lookup known/unknown icons, register custom family

### 5. Generate and ship codepoint mappings for all 6 families
- New: `Sources/Woodcase/IconFonts/LucideCodepoints.swift` (~1952 entries)
- New: `Sources/Woodcase/IconFonts/FeatherCodepoints.swift`
- New: `Sources/Woodcase/IconFonts/PhosphorCodepoints.swift`
- New: `Sources/Woodcase/IconFonts/MaterialSymbolsCodepoints.swift` (shared by all 3 Material variants)
- New: `scripts/generate-icon-codepoints.py` — extracts from npm packages, outputs Swift files
- Generate all Swift files, verify they compile

### 6. Create `PenIconFontRenderer`
- New: `Sources/Woodcase/Rendering/PenIconFontRenderer.swift`
- Logic:
  1. Extract family + name from `IconFontData` (bail if nil)
  2. Lookup codepoint via `PenIconFontRegistry.codepoint(family:name:)` (bail if nil)
  3. Convert `UInt32` → `Unicode.Scalar` → `String`
  4. Create CTFont using family name + size (`min(rect.width, rect.height)`)
  5. For variable-weight fonts (Material Symbols): set `wght` variation axis via CTFontDescriptor
  6. Extract fill color via `PenTextRenderer.extractColor(from:)`
  7. Build CFAttributedString, draw centered in rect
- Red tests: render known glyph → non-blank; unknown → blank; fill color applied; weight affects Material Symbols

### 7. Wire into `PenRenderer`
- `Sources/Woodcase/Rendering/PenRenderer.swift`:
  - Remove `.iconFont` from skip list (line ~160)
  - Add `.iconFont(data)` case in dispatch switch
  - Add to `originalNodeWidth`/`originalNodeHeight`/`effects`/`blendMode` helpers
- Integration test: render doc with icon_font, assert non-blank

### 8. Snapshot tests & re-export references
- Remove lucide.ttf from Tests/Fonts (now in library)
- Update `TestFontRegistration` (may no longer need lucide since library auto-registers)
- Re-render woodcase-app screens, verify MAE improvement
- Re-export Pencil reference PNGs with icons

### 9. Update documentation
- `PenRendering.md` — add Icon Fonts section, document `PenIconFontRegistry` API
- `PenEngine.md` — note icon_font nodes are now rendered
- `README.md` — mention bundled icon fonts and licensing

## Key Files

| File | Change |
|------|--------|
| `Package.swift` | Add `.copy("IconFonts/Fonts")` to library target resources |
| `Sources/Woodcase/Models/PenNode.swift` | Add width/height/effects/blendMode to IconFontData |
| `Sources/Woodcase/PenLayoutEngine.swift` | Add iconFont case to leaf sizing |
| `Sources/Woodcase/PenVariableResolver.swift` | Resolve new IconFontData properties |
| `Sources/Woodcase/Rendering/PenRenderer.swift` | Wire icon rendering, remove skip |
| `Sources/Woodcase/Rendering/PenIconFontRenderer.swift` | **New** — CoreText glyph rendering |
| `Sources/Woodcase/IconFonts/PenIconFontRegistry.swift` | **New** — codepoint registry + font auto-registration |
| `Sources/Woodcase/IconFonts/LucideCodepoints.swift` | **New** — ~1952 icon mappings |
| `Sources/Woodcase/IconFonts/FeatherCodepoints.swift` | **New** |
| `Sources/Woodcase/IconFonts/PhosphorCodepoints.swift` | **New** |
| `Sources/Woodcase/IconFonts/MaterialSymbolsCodepoints.swift` | **New** — shared by 3 Material variants |
| `Sources/Woodcase/IconFonts/Fonts/` | **New** — bundled TTF files for all 6 families |
| `LICENSES/` | **New** — third-party font license attribution |

## Verification
1. `swift test --quiet` — all tests pass including new icon font tests
2. `swiftformat . --lint` — clean
3. Woodcase-app MAE improves (icons now render where before they were blank)
4. Visual inspection of `/tmp/pen-exports/woodcase-app-*.png` shows Lucide icons
5. A fresh project importing Woodcase can render icon_font nodes without any font setup
