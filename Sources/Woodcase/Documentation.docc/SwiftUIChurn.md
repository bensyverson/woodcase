# SwiftUI Churn

How the SwiftUI emitter keeps up with an SDK that moves every year, and what to do at each
Xcode major.

## Overview

SwiftUI's API changes every June. Apple adds APIs and deprecates old ones, but a SwiftUI
deprecation is usually *soft*: the declaration says "deprecated in version 100000", and the
compiler never warns about it. `foregroundColor(_:)`, `cornerRadius(_:antialiased:)`,
`URL(fileURLWithPath:)` and `FileHandle.write(_:)` all compile silently at every deployment
target. So a generator that writes SwiftUI can drift onto dead APIs without a single build
failing. ``SwiftUIEmitter`` guards against that in three layers, cheapest first:

1. **The vocabulary list.** `Tests/WoodcaseTests/Fixtures/swiftui-vocabulary.txt` names every
   SDK API the emitted package can call — SwiftUI's, and Core Text's, Core Graphics',
   ImageIO's, AppKit's, UIKit's and Foundation's — one dotted path per line.
   `SwiftUIVocabularyTests` fails when the emitted code calls something the list lacks.
2. **The audit.** `scripts/swiftui-api audit` checks every listed path against the SDK's own
   symbol graph: it fails on a path that is missing, deprecated (hard or soft), introduced
   above the deployment floor, or unavailable on a floor platform.
3. **The compile and render tests.** The SwiftUI render tests (`SwiftUIRenderTests`,
   `SwiftUIStateRenderTests`, `SwiftUIScreenRenderTests`, `SwiftUISlotRenderTests`) type-check
   the emitted code at the lower floor (`-target …-apple-macos15.0`), then compile it at the
   default one and draw it with `ImageRenderer` against Pen's exports. They catch an
   availability mistake the compiler can see and a *rendering* change no API diff shows: a new
   SDK can move text layout or interpolation without renaming anything. They compile for macOS
   only, so for iOS the audit is the only check.

### The vocabulary list

One path per line, as `scripts/swiftui-api show` prints it: `View.frame(width:height:alignment:)`,
`Alignment.topLeading`, `CTFontGetAscent(_:)`. `#` starts a comment. Overloads share a path, so
`View.padding(_:)` covers the `CGFloat` and the `EdgeInsets` overload alike. Two annotations
may follow a path:

- `@available ios=26,macos=26` — the path is reached only inside an
  `#available(iOS 26, macOS 26, *)` branch of the support file. The audit holds it to that gate
  rather than to the floor, and still fails it if the gate is below the path's introduction.
  `View.lineHeight(_:)` is the one today.
- `@only macos` (or `ios`) — the path is reached only on those platforms: behind
  `#if os(macOS)` (the catalog executable) or `#if canImport(UIKit)` (loading a bundled image).
  The audit does not check it on the others.

The list lives beside the goldens, as a test fixture, because it is test data twice over:
`SwiftUIVocabularyTests` reads it through `SwiftUIFixtures`, and the audit reads it by path.
It is not a resource of the `Woodcase` target, whose `CodeGen/SwiftUITemplates/` directory is
copied verbatim into every emitted package.

**Adding an API is one line** in the section it belongs to. When the emitter starts writing
something new, the test names it — `not on swiftui-vocabulary.txt: .foo(bar:)` — and you add
its path (`scripts/swiftui-api show foo` finds it), then audit.

### What the test reads, and what it cannot see

`SwiftUIVocabularyTests` is a lexer, not a type checker. It reads three sources:

- every support template (``SwiftUIEmitter``'s `supportTemplates`) and every
  `.swift.golden` under `Fixtures/golden/swiftui/`, name and argument labels both;
- the code fragments in the emitter's own string literals (`".underline()"`), by name only,
  since their arguments are interpolated — which reaches a branch no golden exercises;
- the members an emitter site spells from an enum (`.blendMode(.\(name))`): every alignment,
  unit point, blend mode, line cap and join the emitter can write must be listed.

A `{` that ends an `if`, `guard`, `for`, `while` or `switch` line opens the body, since
Swift allows no trailing closure in a condition; anywhere else it is a trailing closure, and
counts as one more argument. Because it cannot type-check, it matches a member by its name
and labels, whatever its owner: a listed `Shape.fill(_:style:)` covers a call to `GraphicsContext.fill(_:)` too, and
the audit then checks only the path you listed. And a name the emitted code declares itself
is taken as the code's own where its use could reach that declaration — a call to a
declared function, an implicit member naming a declared case — so a declared `var frame`
does not hide `.frame(width:)`, but `url.path` does hide Foundation's `URL.path` behind the
emitted `func path(in:)`. A member read through `theme` (`theme.brand`) is the emitted
`PenTheme`'s property for a document variable. List a hidden use by hand; the audit sees the
list, not the code.
Names that are not SDK APIs at all — the Swift standard library, `Synchronization`, SwiftPM's
`Bundle.module`, C struct fields the symbol graph does not record — are on the short,
commented list in `SwiftUIVocabularyExemptions`.

### The corpus

`scripts/swiftui-api fetch` extracts the installed SDK's symbol graphs into
`local/swiftui-docs/<macOS SDK version>/` of the main checkout: SwiftUI, SwiftUICore,
CoreText, CoreGraphics, ImageIO, UniformTypeIdentifiers, AppKit, Foundation and
DeveloperToolsSupport from the macOS SDK, and SwiftUI, SwiftUICore and UIKit from the iOS
SDK (for `Image(uiImage:)` and UIKit). `local/` is gitignored: the corpus is Apple's text and
is never committed; only the script and the list are. `fetch` needs Xcode and the Bash sandbox
disabled, and takes a few minutes; every other verb reads only the corpus.
`scripts/test-swiftui-api` holds the audit's verdicts against a small hand-written corpus.

## The yearly checklist

Once per Xcode major (June betas, then again at the September release), as one leaf:

1. **Fetch the new SDK.** With the new Xcode selected, `scripts/swiftui-api fetch` (sandbox
   off). It stamps a new `local/swiftui-docs/<version>/` beside the old one;
   `scripts/swiftui-api list` shows both.
2. **Diff the vocabulary.** `scripts/swiftui-api diff <old> <new> --only
   Tests/WoodcaseTests/Fixtures/swiftui-vocabulary.txt` names every listed path that was
   removed, newly deprecated, or changed availability, and exits 1 on the first two. Read
   each deprecation's `renamed:`/`message:` (`scripts/swiftui-api show <path>`) for the
   replacement.
3. **Audit at both floors.** From the repository root,
   `scripts/swiftui-api audit Tests/WoodcaseTests/Fixtures/swiftui-vocabulary.txt --floor ios=26,macos=26`
   (the default, ``SwiftUIEmitter/DeploymentFloor/iOS26``) and `--floor ios=18,macos=15` (the
   lower floor, ``SwiftUIEmitter/DeploymentFloor/iOS18``) must both exit 0. Move each finding
   to its replacement in the emitter or a template, regenerate the goldens
   (`UPDATE_GOLDEN=1 swift test --filter "SwiftUIEmitter.*Tests"`), read them, and update the
   list's path.
4. **Compile the goldens at the floor.** Run the SwiftUI render tests
   (`swift test --filter "SwiftUI.*RenderTests"`) on the new Xcode: they compile every
   emitted golden and draw it. A compile error is an availability mistake; an MAE that moved
   is a rendering change — re-baseline it only once you know which side moved.
5. **Look for better APIs.** `diff` without `--only` lists what the year added. Decide
   whether a new API should replace a support-file approximation, the way iOS 26's
   `lineHeight(_:)` replaced `lineSpacing` inside `PenFontModifier`. A replacement above the
   lower floor goes behind `#available` in the support file, never in a component, and its
   path gets `@available`.
6. **Bump a floor only deliberately.** ``SwiftUIEmitter/DeploymentFloor`` is a decision, not a
   side effect of a new SDK. When the lower floor is raised, remove the `#available` branches
   it no longer needs and the `@available` annotations with them, and audit again.

Keep the old stamped copy until the next year's diff is done; delete it after.
