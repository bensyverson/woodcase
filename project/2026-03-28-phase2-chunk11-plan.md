# Phase 2 Chunk 11: Integration Golden Files

**Date:** 2026-03-28
**Status:** Not started
**Prerequisite:** Chunks 1–10 are complete (51 unit tests passing in `ReactEmitterTests.swift`)

## Context

Phase 2 expanded `ReactEmitter` to handle all node types and visual properties. Chunks 1–10 added unit tests with synthetic documents. Chunk 11 is the capstone — golden file tests against the real `woodcase-app.pen` fixture to verify end-to-end correctness.

## Key Files

| File | Role |
|---|---|
| `Sources/Woodcase/CodeGen/ReactEmitter.swift` | The emitter (should NOT need changes) |
| `Tests/WoodcaseTests/ReactEmitterTests.swift` | All tests — add new golden tests here |
| `Tests/WoodcaseTests/Fixtures/golden/` | Golden file directory (currently has `StatCard.tsx.golden` and `theme.css.golden`) |
| `Tests/WoodcaseTests/Fixtures/woodcase-app.pen` | The fixture `.pen` file (~120 frames, ~90 texts, ~40 icons, ~20 components) |

## Existing Pattern

There's already one golden file test at the bottom of `ReactEmitterTests.swift`:

```swift
@Test("Stat Card component emits correct TSX")
func statCardGolden() throws {
    let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
    let doc = try PenParser.parse(contentsOf: url)
    let components = ComponentAnalyzer.analyze(doc)
    let theme = ThemeAnalyzer.analyze(doc)

    let files = ReactEmitter.emit(document: doc, components: components, theme: theme)
    let statCard = try #require(files.first { $0.path.contains("StatCard") })

    let golden = try loadGolden("StatCard.tsx")
    #expect(statCard.content == golden)
}
```

The `loadGolden` helper loads from `Bundle.module` at `Fixtures/golden/{name}.golden`.

## Tasks

### 1. Generate golden files for 4 additional components

For each component, run the emitter, inspect the output, verify it looks correct, then save it as a `.golden` file.

**Components to target (these exercise Phase 2 features):**
- **Lab** (`Component/Screen/Lab`) — gradients, blend modes, transforms, opacity, effects, polygons, strokes, text decorations. This is the visual feature showcase.
- **PencilListItem** — icon fonts, nested frames, strokes
- **ActionButton** — has `_role: button` metadata, fill, corner radius
- **TextInput** — has `_role: textInput` metadata, stroke, placeholder text

**Process for each:**
1. Parse `woodcase-app.pen`, emit all components
2. Find the component by name in the emitted files (e.g., `files.first { $0.path.contains("Lab") }`)
3. Print the output, review it for correctness
4. Save to `Tests/WoodcaseTests/Fixtures/golden/{Name}.tsx.golden`
5. Add a test following the `statCardGolden` pattern

**Important:** The golden file content must match the emitter output exactly (byte-for-byte). The easiest approach is to write a temporary test that prints the output, copy it into the golden file, then convert the test to a comparison.

### 2. Update StatCard golden if needed

Phase 2 may have changed StatCard's output (e.g., if common styles like opacity/transforms now appear even when absent, or if fill handling changed). Check if `statCardGolden` still passes. If not, inspect the diff, verify the new output is correct, and update `StatCard.tsx.golden`.

### 3. All-component crash test

Add a test that emits ALL components from `woodcase-app.pen` and verifies none crash:

```swift
@Test("All components emit without error")
func allComponentsEmit() throws {
    let url = try #require(Bundle.module.url(forResource: "woodcase-app", withExtension: "pen", subdirectory: "Fixtures"))
    let doc = try PenParser.parse(contentsOf: url)
    let components = ComponentAnalyzer.analyze(doc)
    let theme = ThemeAnalyzer.analyze(doc)

    let files = ReactEmitter.emit(document: doc, components: components, theme: theme)
    #expect(files.count >= 20)
    for file in files {
        #expect(!file.content.isEmpty)
    }
}
```

### 4. Verify

1. `swift test --filter ReactEmitterTests --quiet` — all tests pass
2. `swiftformat . --lint` — no lint errors
3. `swift test --quiet` — full suite passes (580+ tests)

## Notes

- The `.pen` file is encrypted and should only be read via `PenParser.parse(contentsOf:)`, not with `Read` or `Grep`.
- Golden files go in `Tests/WoodcaseTests/Fixtures/golden/` and are registered in the test target's resource bundle automatically.
- The component names in the emitter output use sanitized PascalCase (e.g., `Component/Screen/Lab` → `ScreenLab`). Use `.path.contains(...)` to find them.
- This chunk should NOT require changes to `ReactEmitter.swift`. If the golden file output looks wrong, that's a bug from chunks 1–10 to fix first.
- After golden files are created and tests pass, offer to commit all Phase 2 work together.
