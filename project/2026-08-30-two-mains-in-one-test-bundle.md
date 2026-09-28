# Two `@main`s in one test bundle: why `swift test -c release` ran `woodcase`

2026-08-30. Issue `aZADN`. Fixed by splitting `WoodcaseCommandCore` out of
`WoodcaseCommand`.

## The symptom

`swift test -c release` built cleanly, ran the (empty) XCTest phase, and then ended:

```text
Test Suite 'WoodcasePackageTests.xctest' passed …
	 Executed 0 tests, with 0 failures (0 unexpected) in 0.000 (0.000) seconds
Error: Unknown option '--test-bundle-path'
Usage: woodcase <subcommand>
  See 'woodcase --help' for more information.
```

Exit 1, no tests run. The same bundle built for debug ran the full suite. Because of
this, `PerformanceBudget.isOptimized` had never once asserted the release ceilings, and
`scripts/perf-binary` was the only source of release figures.

## The cause

`Tests/WoodcaseCommandTests` depended on `WoodcaseCommand`, an **executable** target.
SwiftPM handles that by renaming the executable's C entry point —
`-Xfrontend -entry-point-function-name -Xfrontend WoodcaseCommand_main`, visible in
`.build/release.yaml` — and aliasing it back for the product link
(`-Xlinker -alias -Xlinker _WoodcaseCommand_main -Xlinker _main`). That rename is not
enough.

`@main` on an **async** entry point makes the compiler emit the entry *body* under the
fixed, module-less symbol `async_Main`. Under `-O` the optimizer replaces the direct
call with a function-signature specialization of the generic reabstraction thunk, and
that specialization's mangled name embeds the constant-propagated callee — again with
no module component:

```text
$sIetH_yts5Error_pIegHrzo_TR10async_MainTf3npf_nTu
  → async function pointer to function signature specialization
    <Arg[1] = [Constant Propagated Function : async_Main]> of reabstraction thunk helper
```

Specializations are emitted as shared (hidden-external) symbols so duplicates across
modules can merge. SwiftPM's derived `WoodcasePackageTests.derived/runner.swift` is an
async `@main` too, so the test bundle had two definitions with the same mangled name
and the linker kept one — the first in the link file list, which was
`WoodcaseCommand.build/WoodcaseCommand.swift.o` (line 557) rather than
`WoodcasePackageTests.build/runner.swift.o` (line 610).

The result: in the release bundle, `main` **and** `WoodcaseCommand_main` load the same
async function pointer.

```text
# release: one async_Main, both entry points loading 0xe98000 + 0xfc8
_main            0x6507a4   adrp x3, 0xe98000 ; add x3, x3, #0xfc8 ; bl _swift_task_create
_WoodcaseCommand_main 0x4f2884  adrp x3, 0xe98000 ; add x3, x3, #0xfc8 ; bl _swift_task_create

# debug: two async_Main bodies and two async function pointers, each local to its
# own object file, each entry point loading its own
_async_Main   0x96cb28 (non-external)   _async_MainTu  0x1f42b48
_async_Main   0xc95c10 (non-external)   _async_MainTu  0x1f4b488
```

`swiftpm-testing-helper` `dlopen`s the bundle, `dlsym`s `"main"`, and calls it. It got
the runner's `main` symbol (confirmed against the dSYM) and `woodcase`'s command tree.
`CommandLine.arguments` inside a dlopened image is the *host* process's argv, which is
why the message names `--test-bundle-path`.

## Reproducing it

Against a release build of the pre-fix tree:

```sh
swift test -c release --filter WoodcaseCommandTests        # the symptom

B=.build/arm64-apple-macosx/release/WoodcasePackageTests.xctest/Contents/MacOS/WoodcasePackageTests
nm -m "$B" | grep -E ' _main$| _WoodcaseCommand_main$|async_Main'
dwarfdump --lookup=0x6507a4 "$B.dSYM"                      # _main is runner.swift's
otool -tV "$B" | grep -A14 '^00000000006507a4'             # both load the same pointer
swift demangle '$sIetH_yts5Error_pIegHrzo_TR10async_MainTf3npf_nTu'

# the helper, by hand
DYLD_FRAMEWORK_PATH=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/Library/Frameworks \
  /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/libexec/swift/pm/swiftpm-testing-helper \
  --test-bundle-path "$B" --testing-library swift-testing
```

## The fix

`WoodcaseCommandCore` is a library target holding every command type, helper and
formatter — the whole of the old `Sources/WoodcaseCommand`. `WoodcaseCommand` is now an
executable target of exactly one file, `Main.swift`, whose `@main` forwards to
`WoodcaseCommandCore.WoodcaseCommand.main()`. `WoodcaseCommandTests` depends on the
library only, so no executable's objects reach the bundle and there is one `@main` in
it again.

Two things that could have gone wrong and did not:

- **The binary-driven tests still work.** `swift test` builds every product of the root
  package, so `.build/<config>/woodcase` is linked even though nothing in the test graph
  depends on it — verified by deleting the binary and watching `swift test` print
  `Linking woodcase`. `CommandFixture` finds it beside the `.xctest` bundle as before.
- **Isolation.** `@main` silently gives the entry point main-actor isolation. Moving
  `main()` into a library dropped that inference and the build failed on the
  `@MainActor` `exitReportingHouseCode`. `main()` now says `@MainActor` out loud, so
  every verb runs where it always ran.

`PackagingTests` is the tripwire: `WoodcaseCommand_main` is exported by the executable
target's objects, so `dlsym(RTLD_DEFAULT, "WoodcaseCommand_main")` finds it exactly when
those objects have been linked into the bundle. It failed before the split and passes
after.

## What the first release run found

Three things, none of them packaging, all of them invisible until now. That is the
argument for keeping `swift test -c release` in the routine rather than treating it as
an occasional check.

1. **`PerformanceBudgetAdvisoryTests` guarded two cases with
   `try #require(!PerformanceBudget.isStrict)`**, meaning to skip them on a strict
   build. `#require` fails; it does not skip. They are `.enabled(if:)` traits now.
   Reproducible in debug all along as
   `WOODCASE_BUDGET_STRICT=1 swift test --filter PerformanceBudgetAdvisoryTests`.
2. **The synthetic `set` ceiling was 500 ms too tight.** It read 800 ms, derived from a
   debug figure ÷ `debugMultiplier`; the first optimized run measured 1023.9 ms. That
   pipeline is almost entirely `JSONDecoder`/`JSONEncoder`, so its real optimizer ratio
   is 1.22×, not 2.5×. Nothing regressed — the number had never been measured. It is
   1300 ms now, and <doc:WoodcasePerformance>'s release column is measured throughout
   for the first time.
3. **A release-only SIGTRAP in `FontResolutionCache`'s deinit**, filed as `euSPm`.
   `PenTextMeasurerFontCacheTests.resolveFontReturnsCachedInstance` crashes the release
   test process deterministically: releasing a `CTFont` out of the cache's dictionary
   trips `__CFCheckCFInfoPACSignature`, so the font was already freed. It is the only
   one of that suite's three tests that lets the `CTFont` escape, i.e. the only one
   holding an extra live reference — the shape of an under-retain rather than an
   over-release. Not caused by this change (nothing here touches fonts) and not fixed
   by it: `swift test -c release` runs to completion and this one test takes the
   process down. That is the leaf's remaining blocker, tracked in `euSPm`.

   > **Corrected 2026-08-30.** "The font was already freed" and "the shape of an
   > under-retain" are both wrong. `MallocStackLogging` shows the font is never freed
   > and its CF retain count is correct; what is corrupted is bit 33 of its `_cfinfo`
   > word — a stray *native* `swift_release`, emitted by the Swift 6.3.3 optimizer as
   > the unguarded destroy of a declared-but-unassigned `var` in the test's own
   > `undisturbed` helper. Nothing in `Sources/Woodcase` was at fault. Fixed by
   > rewriting the helper; see
   > [the finding](2026-08-30-release-only-ctfont-sigtrap.md).

## What this changes elsewhere

`PerformanceBudget.isOptimized` is now reachable, so
`swift test -c release --filter Performance` asserts the release ceilings verbatim.
<doc:WoodcasePerformance> carries the numbers; its "Why the release numbers come from
the binary" section was wrong about the cause ("both bundles carry the expected renamed
`_WoodcaseCommand_main` symbol, so this is a packaging problem") — it was a packaging
problem, but the renamed symbol was never the one that mattered, and the section has
been rewritten in place.
