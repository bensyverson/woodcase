# Woodcase

A Swift library for rendering design documents in the `.pen` format.

New here? The [intro deck](examples/intro-deck/intro-deck.pdf) says what Woodcase is in nine slides — and was itself built by an agent through the CLI ([how](examples/intro-deck/README.md)).

Woodcase reads .pen files from version 2.8 through 2.17 and later 2.x minor versions (with a diagnostic on anything newer than 2.17); it always writes 2.17. Anything older than 2.11 is migrated on load — dropped or renamed properties are reported through an optional `PenDiagnosticCollector`, never silently discarded. See [PenEngine Pipeline](Sources/Woodcase/Documentation.docc/PenEngine.md) for the version gate and migration rules.

Woodcase provides a complete pipeline for working with the .pen design format:

```
.pen JSON
  ↓
Parse
  ↓
Resolve Variables
  ↓
Expand Refs
  ↓
Layout
  ↓
Render
```

## Features

- **Parser** — Decode .pen JSON into a strongly-typed Swift model (`PenDocument`, `PenNode`, 14 node types). Round-trips cleanly: parse → encode → parse produces identical output. Unknown node types and properties are preserved for forward compatibility. Documents older than 2.11 are rewritten to the current 2.17 shape on load.

- **Variable Resolver** — Walk the document tree and replace `$variable` references with resolved literal values. Supports themed variables (e.g. light/dark mode), variable-to-variable chains with cycle detection, and external overrides for runtime values.

- **Ref Expander** — Expand component instances (`ref` nodes) into concrete node trees. Handles descendant property overrides, object replacement, nested refs, and circular ref protection.

- **Google Fonts Resolution** — Automatically download and register Google Fonts referenced in .pen files. Resolves font family names to TTF files from the [google/fonts](https://github.com/google/fonts) repository, with on-disk caching. Supports variable fonts with per-axis weight control.

- **Remote Image Fills** — Image fills whose URL is an `http(s)` address are downloaded before rendering and cached on disk, so a design using stock photography renders the same as one with images beside the file. Relative paths keep resolving against the .pen file's directory.

- **Text Measurer** — Measure text bounding boxes via Core Text's `CTFramesetter`. Supports font family/size/weight/style, letter spacing, line height, and width-constrained wrapping. Defaults to SF Pro.

- **Layout Engine** — Compute layout rectangles for all nodes in a document. Supports horizontal/vertical flex layout, gap, padding, `justifyContent` (start/center/end/space-between/space-around), `alignItems` (start/center/end), `fill_container`/`fit_content` sizing, absolute positioning, and arbitrary nesting.

- **Renderer** — Render a laid-out document into a `CGImage` via CoreGraphics. Supports shapes (rectangles, ellipses, polygons, paths), solid and gradient fills, strokes, text via Core Text, icon fonts (6 bundled families with auto-registration), transforms (rotation, flip), opacity and blend modes, and effects (outer/inner shadows, Gaussian blur).

- **Bundled Icon Fonts** — Six icon font families ship with the library and are auto-registered with CoreText on first use: Lucide, Feather, Phosphor, and Material Symbols (Outlined, Rounded, Sharp). Users can register additional icon fonts via `PenIconFontRegistry.shared.register(family:fontName:mapping:)`. See `LICENSES/` for third-party font attributions.

## Requirements

- Swift 6.2+
- macOS 15+ / iOS 18+

## CLI

Woodcase includes a command-line tool that reads, edits and renders `.pen` files.

### Install

With Homebrew (macOS 15+, Xcode 26; builds from source):

```bash
brew install bensyverson/tap/woodcase
```

Or from a checkout, which installs to `~/.local` (`--prefix` to change it) and upgrades in place when run again:

```bash
scripts/install
```

Either way the binary sits beside `Woodcase_Woodcase.bundle`, its icon fonts and code-generation templates. `swift package experimental-install` copies the binary without it, so `generate swiftui` and icon rendering fail.

Or run it from the checkout without installing: `swift run woodcase --help`.

### The loop

Reading, editing and verifying a design is three commands — no editor, and no
screenshots:

```bash
# 1. Read: what is there, what it is called, and where it landed
woodcase tree design.pen Dashboard/Header --props kind.content

# 2. Write: change one node, guarded by the revision the read printed
woodcase set design.pen Dashboard/Header/Title kind.content="Good evening" \
  --rev e6b9d2897b6dea54 --as ana

# 3. Verify: read it back — as pixels if you need them
woodcase shot design.pen Dashboard --out dash.png --max 800
```

Every read has a `--json` form carrying a revision, every write is attributed and
recorded in an activity log that `woodcase undo` can replay, and the exit code says
what kind of thing went wrong. The log stays with your project — `.woodcase/` beside
your `.git`, added to `.gitignore` the first time it is written. See [Editing from the
Command Line](Sources/Woodcase/Documentation.docc/WoodcaseEditor.md).

### When the answer is a loop

When what to write depends on what a read just said, `woodcase js` runs a JavaScript
program over the file inside one transaction — nothing is written unless the script ends
without an uncaught error:

```bash
woodcase js design.pen -F rows.js --as ana
echo 'doc.lint().length' | woodcase js design.pen -F -
```

`woodcase find` is the read-only sibling: a predicate over the same rows, exiting 1 when
nothing matches. See [The JavaScript Host](Sources/Woodcase/Documentation.docc/WoodcaseScripting.md).

### Rendering

```bash
# Render to PNG at 2x (default)
woodcase render myfile.pen

# Render to PDF with a specific theme
woodcase render myfile.pen --format pdf --theme "mode=dark"

# List theme axes
woodcase themes myfile.pen

# Render with variable overrides (a file's imported libraries are read from beside it)
woodcase render myfile.pen --vars '{"--primary":"#FF0000"}'
```

Run `woodcase --help` for full usage details. See the [CLI documentation](Sources/Woodcase/Documentation.docc/WoodcaseCLI.md) for the verb table, output naming conventions and theme handling.

## Library Usage

```swift
import Woodcase

// Parse a .pen file
let document = try PenParser.parse(contentsOf: penFileURL)

// Expand component references
let expanded = PenRefExpander.expand(document)

// Resolve variables with a theme
let resolved = PenVariableResolver.resolve(
    expanded,
    theme: ["mode": "dark"],
    externalOverrides: ["speaker": .string("Jane Doe")]
)

// Download any missing Google Fonts and remote images
await GoogleFontResolver.shared.prepareFonts(for: resolved)
await RemoteImageResolver.shared.prepareImages(for: resolved)

// Compute layout
let rects = PenLayoutEngine.layout(resolved)
// rects["nodeId"] == PenRect(x: 0, y: 0, width: 400, height: 300)

// Render to image
let image = PenRenderer.render(
    expanded,
    layoutRects: rects,
    size: CGSize(width: 800, height: 600),
    scale: 2
)
```

## Documentation

- [Woodcase CLI](Sources/Woodcase/Documentation.docc/WoodcaseCLI.md) — every verb, its options, and the exit codes it can return
- [Editing from the Command Line](Sources/Woodcase/Documentation.docc/WoodcaseEditor.md) — the read–write–verify loop, addressing, property paths, batches, revisions and undo
- [PenEngine Pipeline](Sources/Woodcase/Documentation.docc/PenEngine.md) — pipeline stages, design patterns, and key architectural decisions
- [Rendering](Sources/Woodcase/Documentation.docc/PenRendering.md) — rendering architecture overview
- [Mesh Gradients](Sources/Woodcase/Documentation.docc/PenMeshGradients.md) — the pure-Swift tessellator and rasterizer behind `mesh_gradient` fills, and its adaptive error bound
- [Icon Fonts](Sources/Woodcase/Documentation.docc/PenIconFonts.md) — bundled icon font families, versions, weight support, and custom registration
- [Google Fonts](Sources/Woodcase/Documentation.docc/PenGoogleFonts.md) — automatic font resolution, caching, and variable font support
- [Remote Image Fills](Sources/Woodcase/Documentation.docc/PenRemoteImages.md) — downloading and caching the images that `http(s)` image fills point at
- [Import Namespaces](Sources/Woodcase/Documentation.docc/PenImportNamespaces.md) — how library imports are namespaced to prevent identifier collisions
- [Pen Interoperability](Sources/Woodcase/Documentation.docc/PenInteroperability.md) — rendering differences between Woodcase and the format's own editor
- [Code Generation](Sources/Woodcase/Documentation.docc/PenCodeGen.md) — deterministic code generation from .pen files to React + Tailwind
- [Editing Documents](Sources/Woodcase/Documentation.docc/EditingDocuments.md) — mutable flat-store editing model with typed operations and round-trip materialization
- [The Activity Log](Sources/Woodcase/Documentation.docc/WoodcaseActivityLog.md) — the append-only JSONL record of every committed edit: its wire format, where it lives, and how to follow it
- [The Viewer](Sources/Woodcase/Documentation.docc/WoodcaseViewer.md) — the local, read-only web view of your .pen files, and the JSON, PNG and Server-Sent Events API it is built on
- [DESIGN.md](DESIGN.md) — the viewer's design system: tokens, color rules, typography and component atoms, in the [design.md](https://github.com/google-labs-code/design.md) format
- [CRDT Architecture](Sources/Woodcase/Documentation.docc/CRDTArchitecture.md) — collaborative editing via CRDTs: LWW registers, RGA lists, Kleppmann tree moves, and the sync protocol
- [Performance](Sources/Woodcase/Documentation.docc/WoodcasePerformance.md) — the measured budgets for parsing, layout, rendering and editing, and how to reproduce them

Generate DocC documentation locally:

```bash
swift package generate-documentation

# Serve the docs:
swift package --disable-sandbox preview-documentation --target Woodcase
```



## Adding Woodcase to Your Project

### Swift Package Manager

```swift
dependencies: [
    .package(path: "../Woodcase")
]
```

## Testing

```bash
swift test
```

> **Note:** `PenTextMeasurerTests` are skipped when running via `swift test` because Core Text requires a hosted environment. Run those tests from Xcode.

## License

MIT — see [LICENSE](LICENSE). Bundled fonts carry their own licenses in [LICENSES/](LICENSES/).
