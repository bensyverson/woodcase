# Gotchas

Project-specific traps that cost real time and that no general rule predicts. Read at session start; append when you hit one.

- **Fix at the source when you can.** A gotcha is a bug report on our tooling, not a permanent fact — if it can be fixed in code, file it in `job` and fix it instead of recording it here.
- **Delete anything that becomes obvious, gets fixed, or stops recurring.** Keep this list short; a long list is one nobody reads.
- **Feedback about `AGENTS.md` itself** — a rule that was wrong, misread, or cost time — goes here too, prefixed `rule:`. It is harvested when the shared rules are reviewed.

Format: one dated H2 headline, then one paragraph. If an entry needs more than that, it's a finding — write it as a dated doc under `project/` and link it from the paragraph.

---

## 2026-08-29 — Pen.app never saves for you; the `pen` CLI does

The Pen MCP (`execute`) mutates the open document in memory only; Pen.app has no autosave, and `osascript … keystroke "s"` is refused (no Accessibility grant). The fix is the `pen` CLI (0.3.5, Homebrew; needs a one-time `pen login`, which is interactive — ask Ben): `printf 'save()\nexit()\n' | pen interactive --app desktop` saves the app's active document to its own path, sandbox off. `execute`'s `filePath` does not open a file either — `open -a Pen <file>` first, or `Get` silently reads whichever document is active. `pen interactive --in <file> --out <file>` runs the same engine headless with a real `save()` and persistent globals; see [the pen CLI finding](2026-08-29-pen-cli.md).

## 2026-08-29 — Pen's PNG export is bounded by the overflow, not by the frame

`Export(["root"], "png", dir, {scale:1})` on a 900×300 frame produced a **900×340** image: the export box is the union of the frame and everything drawn outside it, and the extra 40 px sat *above* the frame because a `viewBox` path overflowed upward. So a reference PNG's origin is not necessarily the frame's origin, and a snapshot test that renders the frame at (0,0) will be misaligned by exactly the overflow. Since 2026-09-28 (`Wkr2Pd`) `paintedExtent(of:rect:layoutRects:)` computes that box, and the render-test helper places Pen's references by it; use it rather than measuring by hand.

## 2026-08-29 — A schema doc comment can describe the position anchor, not the render pivot

The 2.17 schema's `rotation` comment ("Degrees CCW around top-left corner") names the layout **anchor**, not the CG pivot. Settled 2026-09-27 (`nAuBKh`, `cqBw2i`): Pen turns and flips every node its parent does not lay out (roots, `layout: none` and group children, absolute children of flex frames) about its `x`/`y` anchor, and its layout reports the bounds of the result; `PenLayoutEngine.freeRect(of:…)` writes exactly that, and the CG centre pivot inside that rect draws the anchor turn. Only flex-flow children keep the "slot grown to the turned bounds" rule. React, which places free nodes with CSS at their `x`/`y`, pivots at the anchor (`TransformPivot`). Plausible literal readings were wrong in both directions here: measure any pivot change with `scripts/pen-oracle` on a probe fixture first. History: [the group anchor finding](2026-08-29-absolute-fit-content-and-the-group-anchor.md).

## 2026-08-29 — Wall-clock assertions, *and wall-clock budgets*, are unreliable in the parallel suite

`swift test` runs the suite concurrently, and under that load a `Task.sleep(for: .milliseconds(10))` can take **twelve seconds** to resume. A `PenFileTransaction` lock-timeout test that asserted "a 200 ms timeout returns in under 5 s" passed alone and failed in the full run for that reason alone — the timeout itself was enforced correctly against `ContinuousClock`. Assert the observable outcome (the typed error, the state on disk); if you must bound elapsed time, bound it at "not hung" scale (tens of seconds), never near the interval under test. The same is true of a budget you pass *into* the code — a `timeout:` argument, a `PageHost` load budget, a poll loop's bound — and that face is harder to spot, because it fails as the product misbehaving rather than as a clock: a 5 s WebView budget answered `.timeout` where the test asserted `.javaScriptError`, and a 10 s lock budget gave a waiter roughly one `flock` attempt before it reported a real `lockTimeout`. Both are now 60 s; see [the finding](2026-08-31-load-shaped-budgets.md). One trap rides along: a poll loop that checks its deadline *before* the condition and never re-checks after it can sleep straight past the moment the condition came true — the deadline bounds how long you wait, not whether you look. `waitUntil` did exactly that and reported four timeouts nothing had earned.

## 2026-08-29 — rule: editing any source file while `swift test` is building aborts the run

SwiftPM fails the whole build with `error: input file '<path>' was modified during the build`, and under `--quiet` that surfaces only as a bare `error: fatalError` after several minutes. This cost two full build cycles here, because the natural agent rhythm — background the test run, keep editing while it compiles — is exactly what breaks it. Treat a running `swift build`/`swift test` as a lock on the worktree: do read-only work while it runs, and batch edits between runs. Belongs in `project/agents/harness.md` alongside the sandbox facts.

## 2026-08-29 — A timing measured while agents build is not a timing

The suite-speed leaf was filed on "95 s full suite, 78 s WebViewRegression". On a quiet machine the same unchanged suite was 18.7 s: four sibling agents' `swift build`s had inflated it 4×. Re-measure before treating a recorded figure as a premise, quote minima of several runs, and say in the doc whether the machine was loaded (`project/2026-08-29-test-suite-speed.md` shows the shape).

## 2026-08-29 — A verb that never exits must flush stdout itself

`woodcase serve` prints its URL and then waits for a signal. Redirected to a file or a
pipe, stdout is block-buffered, so the URL sat in the buffer forever and
`woodcase serve | head -1` hung — the one thing the "stdout is the API" rule exists to
make work. Every other verb gets away with never flushing because every other verb ends,
which is why no rule predicts this. `ServeCommand.report(address:port:files:)` calls
`fflush(stdout)`; any future verb that outlives its own output must do the same.
Reproduce with `woodcase serve --port 0 > out.txt & sleep 2; cat out.txt`.

## 2026-08-29 — `PenLayoutEngine` rects are parent-relative

Only a top-level node's rect is in canvas coordinates; a nested node's `x`/`y` is its offset inside its own parent (`layout-deep-nesting.layout.json`: a leaf four levels down reads `x:0,y:0`). Anything that reads one rect out of the map and treats it as absolute is wrong below depth 1 — that is how `shot --outline` drew every nested box at the wrong place until wlAte. Compose the offsets with `PenLayoutEngine.absoluteRects(under:in:layoutRects:)`, which is the one walk `shot --outline` and the viewer's `ArtboardLayout` both use; never hand-roll a second one. "Relative to the parent" means relative to the parent's own coordinates, which are not always its rect's corner (2026-09-27, `cqBw2i`/`INL8Zi`): a **group**'s children are measured from its anchor while its rect is their union, which can start anywhere (Pen's own layout does this), and a **turned** parent's children are measured in its unturned box, centred in its rect. `absoluteRects` composes both; adding a parent's rect origin to a child's rect is wrong for either.

## 2026-08-30 — `swift test --filter` matches the identifier, not the display name

`--filter "woodcase activity"` and `--filter "--follow stops when …"` both match **zero**
tests and report a green run of nothing — the filter is a regex over `SuiteType/functionName`,
not over the `@Suite`/`@Test` display string. Since almost every suite here is named twice
(`@Suite("woodcase activity") struct ActivityCommandTests`), the name in the output is
usually the one that does *not* work. Filter on the Swift names: `--filter ActivityCommandTests`,
`--filter followStopsWhenOrphaned`. A filter that matched nothing still prints
`Test run with 0 tests ... passed`, so it looks like a pass.

## 2026-08-29 — A `#require` inside a `#require` will not compile

`try #require(doc.node(id: try #require(created.children.last).id))` fails the build with
`error: recursive expansion of macro 'require(_:_:sourceLocation:)'`, pointing at a column
inside the expanded code rather than at the nesting — it reads like a broken toolchain.
Swift Testing's macro cannot expand another of itself in its argument. Hoist the inner one
to its own `let` line. Same for `#expect(… "\(try #require(x))" …)`.

## 2026-08-30 — A declared-but-unassigned `var` in a generic function is miscompiled at `-O`

Swift 6.3.3 emits, at `-O` **without** whole-module optimization, an *unguarded* release
of the previous value of a local `var` that was declared without an initializer and is
assigned inside a loop, when its type mixes a native class with the function's generic
parameter. On the first iteration there is no previous value, so `swift_release` runs on
whatever the last call left in `x0`. In `PenTextMeasurerFontCacheTests.undisturbed` that
was a live `CTFont`; the native release decrements bit 33 of CoreFoundation's PAC-signed
`_cfinfo` word, and the trap only fires much later, on the next release that reaches CF's
dealloc path — which is why the crash reported a healthy object as freed. SwiftPM builds
library targets with `-wmo`, so only the release **test** build compiles this way; that
is the whole reason `swift test -c release` was the only thing that ever saw it. Write
the loop so each attempt is returned on the spot rather than parked in an unassigned
`var`; `scripts/swift-di-miscompile` says whether the toolchain still needs that, and
[the finding](2026-08-30-release-only-ctfont-sigtrap.md) has the disassembly.

## 2026-08-30 — An `NWListener` with no `newConnectionHandler` fails with `EINVAL`

`listener.start(queue:)` on a listener whose `newConnectionHandler` has not been set
reports `.failed(POSIXErrorCode(rawValue: 22): Invalid argument)`. Set the handler first
and the same listener, same parameters, same process reports `.ready` with a port. It has
nothing to do with loopback, `requiredLocalEndpoint`, `allowLocalEndpointReuse`, SwiftPM,
descriptor pressure or load — which is exactly why `HTTPServer.start(port:)` never had the
problem: it assigns `newConnectionHandler` before it starts. Root-caused 2026-08-31 (leaf
`3uBxi`); the earlier text of this entry blamed the loopback parameters and was wrong.
Reproduce with `swift scripts/probe-network-seam.swift` (sandbox off), verdicts `L1` and `L2`.

## 2026-08-30 — `DispatchSemaphore.wait` inside a synchronous `@Test` starves the very queue it's waiting on

A synchronous (non-`async`) `@Test` function that blocks on `DispatchSemaphore.wait()`
for a `DispatchQueue.global()` callback to signal it took the full timeout every time —
30 s or more — even alone, never the callback's real, near-instant latency. Swift
Testing schedules a plain `throws` test's body on its own limited cooperative pool, which
overlaps enough with `DispatchQueue.global()`'s worker threads under this suite's load
that blocking one starves the other's chance to run the state handler that would signal
it. Await the same async continuation the code under test would use
(`withCheckedThrowingContinuation`, the way `HTTPServer.start(port:)` does) rather than
gate an async callback behind a synchronous semaphore wait in test code.

## 2026-08-30 — a second `scrollIntoView` in `viewer.js` silently undoes the first

`viewer.js` reveals the selected outline row with `row.scrollIntoView({block: "nearest"})`.
Adding a second reveal for the artboard map — `box.scrollIntoView({block: "nearest",
inline: "nearest"})` on an element in a *different* pane, running later in the same task —
made `ViewerBrowserTests.selectionScrollsTheOutlineToItsRow` fail on the fresh-load leg,
and only under the full `swift test`: the browser suite on its own passed three runs in a
row, so it reads as a flake rather than as the regression it is. `scrollIntoView` is not
scoped to one scroll container; it walks every scrollable ancestor up to the viewport, and
two of them issued in one task do not compose. Scroll the container you mean directly
(`element.scrollLeft += box.left - frame.left`) whenever the page already has a
`scrollIntoView` somewhere else, and confirm any new viewer scroll behaviour against the
**full** suite, never the browser filter alone.

## 2026-08-30 — Elementary *merges* a conditional `style` onto the element's own

`.attributes(.style("--v-actor: …"), when:)` on an element that already declares
`.style("--v-x: …")` does not replace it: Elementary joins the two with `;`, which is
exactly what `OutlineRow`'s touched-row colour relies on and is invisible unless you read
a golden. The trap is the other direction — repeating the base style inside the
conditional block, which duplicates every property and yields
`style="--v-x: 1;--v-x: 1;--v-actor: …"`. Pass only what the condition adds. The same
merge applies to `class`; every other attribute is appended as a second attribute, in
declaration order, which is why a golden's attribute order is class, data-*, title,
style, href, then whatever the conditional block added.

## CoreText registration from Data silently fails — register fonts from file URLs

`CTFontManagerRegisterFontDescriptors` rejects descriptors made by
`CTFontManagerCreateFontDescriptorsFromData` (no `kCTFontURLAttribute`; error 303 goes
only to the optional handler). Use `CTFontManagerRegisterFontsForURL`, writing bytes to
a temp file if they have no disk home. Trap variant: test setup registered fixtures
from URLs while production registered from data, so 3000 green tests never saw the
production path fail — when a test helper and production do "the same thing" through
different APIs, the difference is the bug. See
project/2026-08-30-font-registration-from-data.md.

## 2026-08-30 — `MouseEvent`'s `clientX` is an integer, and the stage divides by a fraction

A browser test that clicked the middle of a node's box on the render — coordinates computed
in *layout points*, converted with `box.left + point.x * scale` — selected a node **two
levels up the tree**, deterministically, while an identical-looking scan said the point
belonged to the intended node. `MouseEventInit`'s `clientX`/`clientY` are `long`: WebKit
truncates the fractional part. The script then divides by `--v-scale`, which `fitStage()`
sets to a fraction (about 0.5 at a 1600×900 viewport), so half a pixel of truncation
becomes a point or more in layout space — enough to land outside a 14-point-tall text box
and hit its grandparent instead. It reads as a bug in the hit test, which is where an hour
goes. Pick the click point in **whole client pixels** and convert it *back* to layout
points before accepting it, which is the only version of the arithmetic the page will ever
see; `ViewerSelectionBrowserTests.Bench.clickOnRender` does exactly that and is the helper
to copy.

## 2026-08-30 — "Did the page reload?" cannot be asked about a *back* navigation

A browser test proves an in-place navigation by stamping a marker on `window` that a
document replacement wipes (`window.__woodcaseNavProbe`), and that works perfectly in
the forward direction. It is useless for `history.back()`: WebKit's back/forward cache
restores the previous document *with its JavaScript heap*, so the marker written before
a real reload is still there afterwards — and `performance.getEntriesByType("navigation")`
still reports one entry, so that does not separate them either. A back-navigation test
written this way passes identically against the reloading code and the fixed code, which
is a test of nothing. Assert the *forward* step was in place first, in the same test:
once it is, `history.back()` is a `popstate` by construction and the assertions after it
mean something. `ViewerNavigationBrowserTests.historyStepsBackToThePreviousArtboard`
is written that way and says so.

## 2026-08-30 — A character the ellipsis ate reports a *zero-width* rect, not one off-screen

Proving which end of an overflowing string was truncated looks like a geometry question:
put a `Range` around the first character and check it sits outside the box. It does not.
WebKit gives a clipped character a rect of **zero width, parked at the clip edge** — in
`ViewerChromeBrowserTests.aLongSelectionPathIsFrontTruncated` the head came back as
`364..364` against a box of `358..827`, six pixels *inside* the left edge, so an assertion
of "head.right < box.left" fails against code that is working perfectly. Test `width === 0`
for "not drawn" and `width > 0` plus a flush edge for "still drawn". The same run also
showed the honest way to size the box for such a test: below about 700 px of viewport the
three panes are already wider than the window and the canvas column collapses to nothing,
so a "narrow window" truncation test measures a broken layout instead. Use a full-width
window and a long enough name.

## 2026-08-31 — rule: a docs-only commit does not need the suite

"Run the full suite before every commit" is for commits that can change behavior.
Ben confirmed a commit that touches only Markdown/docs skips `swift test`; the
pre-commit hook still runs (it formats staged Swift files — none — and mae-check).

## 2026-08-31 — `cp` over an installed binary earns a signature SIGKILL

Replacing `~/.swiftpm/bin/woodcase` with `cp .build/release/woodcase ~/.swiftpm/bin/woodcase`
produced instant, silent exit 137 on every subsequent run: macOS kills a binary whose
inode was rewritten under its ad-hoc code signature, with no message anywhere. `rm` the
target first (or `mv` the new binary in) so the install lands on a fresh inode.

## 2026-08-31 — ArgumentParser cannot express an option whose value may be omitted

`--props` written bare fails during parsing — `Missing value for '--props <props>'` —
before the verb can default it, and there is no declaration that avoids it: an array
option with `parsing: .upToNextOption` throws `errorForMissingValue` when zero values
follow (`ArgumentSet.swift`, the `.upToNextOption` case), and `@Option var x: [T]?` has
no overload at all. Half an hour went into trying declarations. If a flag has to accept
being written bare, the value is filled in before the parser sees it —
`BareOptionValue.filled(_:)`, called from `WoodcaseCommand.main`'s `parseAsRoot(_:)` —
and the fill-in belongs in that option's own help so it is discoverable.

## 2026-08-31 — A wedged suite whose sample holds *no* frames of ours is a suspended `await`

A run stopped at 0 % CPU whose `sample` contains nothing of ours is not hung in the code
the sample shows: a Swift task suspended at an `await` — an unresumed continuation, a
feed that never yields — has no thread and therefore no stack. Whatever Woodcase frames
the sample *does* contain are the code still running, usually a poll loop, and reading
that as the culprit sends you into the wrong subsystem (it sent leaf 8kAHL into the
activity log for a week). Find the host with `ps -Ao pid,ppid,etime,pcpu,args | grep
swiftpm-testing-helper`, `sample <pid> 3 -f <file>` sandbox off, and when the sample is
empty of our code go looking at what the test was *waiting for*. The 2026-08-31 instance
was three unbounded Network.framework callbacks, fixed with ``ResumeOnce`` (leaf `3uBxi`,
reproducible with `scripts/soak-tests 2 <log> --load 6`); the rule it left is that **an
`await` on a callback you do not own needs a deadline you do**. Findings:
[the two samples](2026-08-31-follow-is-a-value.md) and
[the cause](2026-08-31-the-await-that-cannot-resume.md). The 2026-09-07 entry below is
the same face with a different cause — a slow browser phase — so measure with a longer
watchdog before believing the sample.

> **2026-09-26 (leaf `DpQmXu`):** the wedges of 2026-09-07 to 2026-09-26 are this face
> again, and the best-supported reading is that the await nobody resumed was a call into a
> headless page: `PageHost.evaluate` and `WKWebView.takeSnapshot` are completion handlers
> with no deadline, and one that never answers reproduces the wedge's sample exactly. `BoundedWait` (which
> used to wait for a job that ignores cancellation, and so could not bound one) now
> abandons it; every browser test calls `boundedLoad` / `boundedEvaluate`. See
> [the page that never answers](2026-09-26-the-page-that-never-answers.md).
>
> **Updated 2026-09-26 (leaf `QZ41uc`):** SleepyHollow now bounds those calls itself —
> `PageHost.callBudget` (60 s default) on `evaluate`, `snapshot` and load's console count,
> a `.timeout` `SleepyError` past it, and `PageHost.abandonedCall` set so a pool discards
> the host. Page calls no longer need `BoundedWait`; the rule stands for every other
> callback you do not own.

## 2026-08-31 — A public signature change can leave SwiftPM linking stale test objects

Turning `ActivityRecorder.apply`'s return from `ActivityEvent?` into `ActivityEvent` built
the library fine and then failed at *link* time with `ld: symbol(s) not found`, naming
closures in `WoodcaseViewerTests` and `RenderCacheTests` that still carried the old
`-> ActivityEvent?` type. Re-running the build reproduced it exactly: SwiftPM had not
recompiled those test files even though the module they import had changed shape. It reads
like a broken toolchain, and `swift build` alone never converges. `touch` the test files
that use the changed symbol and build again — a full `.build` wipe is a ten-minute
alternative for the same result.

A second face, 2026-09-07: **adding a case to an enum** another module stores as an
`Optional`. `Optional<Kind>` spells `nil` with the tag after the last case, so an object
compiled against the old `ActivityEvent.Kind` writes `nil` where the new layout reads
`.external`, and the failures are impossible on their face — `(change.op → nil) == nil`
failing, a `.set` read back as `.external` — in suites nobody touched
(`ViewerEndpointsTests`, `ChangeCoordinatorTests`, `ViewerServerTests`), while the same
branch is green in a fresh worktree. `touch` the consuming module's sources and tests and
build again; an impossible assertion failure in an untouched suite is this, not a bug.

## 2026-08-31 — A wait after an irreversible step tests nothing

`ViewerFollowBrowserTests.unreadDotUntilViewed` wrote a node, navigated straight to the
map, then waited 30 s for the map to show an unread dot — and failed two of five loaded
soak runs. The dot lives in the *browser's* `localStorage`, written by `ViewerScript`'s
`change` handler when the event arrives over the stream, never in the markup the server
sends. A page that navigates away before the event lands never runs the handler, so the
mark is never written and **no amount of waiting afterwards can recover it**; the generous
bound only decided how long the suite took to report a race it had already lost. Bound the
wait on the state the later step *consumes* (here: `localStorage.getItem('woodcase.unread:<file>:<artboard>')`),
not on the thing you hope that state will produce. Any wait placed after a navigation, a
teardown or a page swap has the same hole. [The finding](2026-08-31-follow-is-a-value.md)
has the before and after.

## 2026-09-02 — Exactly one test per run may watch a font family go from absent to present

CoreText registration is process-global and irreversible. `GoogleFontResolverTests` owns
"JetBrains Mono" (the only non-system TTF in the repo) for that transition; a second suite
staging the same family turns the first red, because `resolve()` short-circuits on an
already-available family. New font tests use an already-placed family (IBM Plex Sans, Inter) or a
never-placeable one. The same irreversibility makes suite order matter: since 2026-09-26
`TestFontRegistration` registers Inter, so a suite that renders or measures Inter (or Plex) must call
`registerTestFonts()` itself — relying on another suite having done it measured Inter boards in SF Pro
or Inter depending on which ran first (banking: 3.35 one way, 5.99 the other before hwCwvs).

## 2026-09-02 — `swiftformat` in a worktree needs `--config .swiftformat`, and still says it ignored one

`swiftformat . --lint` run from a worktree prints `Ignoring config file at
/Users/ben/git/Woodcase/.swiftformat` and lints with the defaults, which disagree with the
repo. Pass `--config <worktree>/.swiftformat` explicitly. The run then uses that file but
*still* prints the same "Ignoring" line, naming the main checkout's config it found by
walking up; three agents read that as "my config was ignored" and re-ran. The proof it was
used is the file count: the repo config skips 87–89 files, the defaults skip none.

## 2026-09-07 — `Task.detached` will not compile inside a function with an `isolated` parameter

Swift 6.3.3 rejects `Task.detached { … }` written in the body of a function that takes
`isolation: isolated (any Actor)? = #isolation` with *"pattern that the region-based
isolation checker does not understand how to check. Please file a bug"* — pointing at
the `Task.detached` column, which reads as a broken toolchain rather than a rule.
Binding it to a `let` first does not help. Hoisting the detach into a plain
`nonisolated static` helper one call out compiles and changes nothing about what runs
where; `EditableDocument.buildDocumentOffActor(from:)` is the shape, and says why in
its own doc comment. Worth knowing before the scripting host writes its first
isolation-agnostic API.

## 2026-09-07 — A test that reads a 1.2 s UI flash is reading the machine, not the page

`ViewerCopyChipBrowserTests` clicked an id chip and polled for the `is-copied` class the
handler removes after 1200 ms. One `PageHost.evaluate` round trip into a headless page
under a loaded suite can take longer than that, so the poll saw nothing and reported a
copy that had in fact happened — it passed alone, three-for-three, and failed
three-for-three in the full run. Have the *page* write the fact down as it happens (a
`MutationObserver` setting `window.__flashed`) and assert that afterwards; a fact
outlives the flash it came from. The same test also asserted the system pasteboard,
which no headless harness owns: SleepyHollow's window is never made key, so
`document.hasFocus()` answers whatever the machine's front window makes it answer, and
WebKit refuses both `navigator.clipboard.writeText` and `execCommand("copy")` on an
unfocused document. Stub the clipboard seam and assert what the handler did with it.
This surfaced when the editing layer left the main actor: page building stopped taking
turns with WebKit on one actor, every browser round trip got slower under load, and the
flash started outrunning the poll. Removing an accidental throttle exposes every test
that was quietly relying on it.

## 2026-09-07 — A soak `TIMEOUT` with no frames of ours in the sample may be a slow browser phase, not a hang

Two soak runs of the un-pinned branch reported `TIMEOUT after 280s` and sampled a test
host with **no Woodcase frames at all** — the 2026-08-31 "third face", which reads as an
unresumable `await`. It was not one: at `--timeout 600` the same branch passes 3/3, one
run taking 586 s. The browser tests' `waitFor` polls with `Task.sleep`, and a sleeping
task has no thread, so a suite that is merely slow in that phase looks exactly like one
that is hung. Measure with a longer watchdog before believing a sample; `scripts/soak-tests`
now defaults to 600 s for this reason. With every WebKit-dependent test skipped the branch
and `main` are indistinguishable (56–58 s either way), so the tail is WebKit's and the
numbers are in [the finding](2026-09-07-unpinning-and-the-loaded-soak.md).

## 2026-09-07 — `JSContext.evaluateScript(withSourceURL:)` reports the URL back, not the name you gave

An exception's `sourceURL` is the *absolute* URL the source was evaluated with, so
`URL(fileURLWithPath: "run.js")` comes back as `file:///…/worktree/run.js` and
`"<stdin>"` comes back with the working directory in front of it. Reconstructing the
caller's name from that string is how a report ends up naming a file nobody wrote — the
first cut of `ScriptFailure` did exactly that and located a two-source failure in the
wrong source, which then quoted no line at all because the text was keyed by name.
Record the URL-to-name mapping on the way in (`ScriptFailure.Evaluated`) rather than
guessing it on the way out.

## 2026-09-07 — "The compiler accepted it" means nothing when the build is already red

An agent verifying the un-pin in Penumbra reported that passing the now non-Sendable
`EditableDocument` into an actor method drew *no diagnostic* under Swift 6 complete
checking, and an issue was filed against the library docs on the strength of it. The
build it observed was failing at 31 unrelated .pen 2.17 model errors, and type-checking
stops there — the sendability pass that refuses the send never ran. Once the port cleared
those errors the compiler produced the seven refusals the docs predict. A claim of the
form "the compiler allowed X" is evidence only from a build that otherwise succeeds; from
a red build, "no error at line N" says nothing about line N. Get to green first, or say
plainly that the observation is unverified.

## 2026-09-08 — DocC refuses a reciprocal Topics entry, and a `--target Woodcase` build cannot link a sibling module's symbol

Two warnings a new article in the catalog earns for doing the natural thing. Curating
`<doc:WoodcaseEditor>` under the new article's Topics when WoodcaseEditor.md already
curates the new article draws `Organizing 'Woodcase/WoodcaseCLI' under
'Woodcase/WoodcaseScripting' forms a cycle`; link the other page from prose instead, which
does not curate. And a `` ``WoodcaseScripting/ScriptHost`` `` link costs `'ScriptHost'
doesn't exist at '/Woodcase/WoodcaseScripting'` — the catalog is one module's, so a
sibling target's types are named in code voice with the target they live in
(WoodcaseViewer.md and WoodcaseScripting.md both do). The coverage flag is
`--coverage-summary-level brief`, not `--level brief`, which docc reads as a catalog
path and reports as a `.doccarchive` that "couldn't be moved". Baseline before judging:
`swift package generate-documentation --target Woodcase` prints 78 warnings today, all
pre-existing WoodcaseViewer link warnings.

## 2026-09-08 — rule: a completion poll that runs `kill -0` inside the Monitor tool reports a wedged process as finished

An agent waited on its `swift test` with a Monitor loop around `kill -0 <pid>`. Monitor
runs sandboxed with no way to disable it, so `kill -0` fails for a reason that has nothing
to do with the process, and the loop read the failure as "gone" — a suite that had
wedged (issue `DpQmXu`, third occurrence) was reported as a clean pass. Poll with
`ps -p <pid>` in a plain Bash call, or better, run the suite in the foreground with a
timeout and verbose output into a log, so a wedge names its in-flight tests. Belongs in
`project/agents/harness.md` beside the sandbox facts.

## 2026-09-08 — `help design` has no headroom: check the line budget before adding to it

`HelpCommandTests.designTopicLineBudget` was 145 and the topic was exactly 145 lines, so
the first three lines any agent adds fail a test in a file it never opened, and only the
full suite shows it. Trim to the claim, put the rest behind the verb's own `--help` with a
row in the SEE ALSO block, then raise the budget in the same commit with the reason in its
doc comment — the constant's own DocC already says "raise it again deliberately, never
silently".

## 2026-09-08 — a `#`-heavy JSON literal needs `##"…"##`

A Swift raw string `#"…"#` holding a hex colour ends early: `"#fff"` contains the closing
delimiter `"#`. Every batch-line test fixture with colours in it wants `##"…"##`. The
compiler says `expected ',' separator`, which points at the wrong thing.

## 2026-09-26 — Inside the Claude Code sandbox, Apple TLS cannot verify any certificate

The harness's Seatbelt profile denies `com.apple.trustd.agent` unless the user sets
`sandbox.enableWeakerNetworkIsolation: true`. Without it every `URLSession` HTTPS request
fails `-1202` (certificate untrusted), and `SecTrustEvaluateWithError` returns
`errSecInternalComponent` (`-26276`) even offline. It reads as a MITM proxy, but it is
not one: curl sees the real chain, because it uses LibreSSL and `/etc/ssl/cert.pem`. The
sandbox also has no DNS, so a `localhost` proxy must be dialled as `127.0.0.1`. Neither
can be fixed from our side. On macOS the shared resolvers work around it: `StandardDataFetcher`
retries a `certificateTrustUnavailable` fetch with `/usr/bin/curl` (`CurlDataFetcher`), so a
render downloads anyway — but any *other* `URLSession` HTTPS code run in the sandbox still
fails. Prove network code with `scripts/probe-proxy-egress` (sandbox off), and
`--deny-trustd` for the fallback. See [the finding](2026-09-26-sandbox-font-downloads.md).

## 2026-09-26 — `FileManager.default.temporaryDirectory` ignores `$TMPDIR` on macOS

It resolves to the per-user `/var/folders/…/T`, not `$TMPDIR`, and the Claude Code Bash
sandbox allows writes to `$TMPDIR` (`/tmp/claude-501`) but not there. Code that stages a
file in it fails sandboxed with `NSCocoaErrorDomain 513` (write permission denied), while
every test passes, because tests run with the sandbox off. `CurlDataFetcher` first wrote
curl's body to a temporary file and failed exactly this way; it now reads a pipe.
Stage scratch files through `ScratchDirectory`, which honours `$TMPDIR`.

## 2026-09-26 — Core Image needs a GPU, even with `useSoftwareRenderer`

Inside the Claude Code Bash sandbox `MTLCreateSystemDefaultDevice()` is `nil`, and Core Image renders through Metal whatever `CIContextOption.useSoftwareRenderer` says (`CI_PRINT_TREE=1` shows a "metal context"), so `createCGImage` returns `nil` and any `guard … else { return }` around it turns the effect into a silent no-op. The same holds on any machine without a reachable GPU. The renderer's blurs no longer use Core Image (`PenGaussianBlur`, Accelerate, leaf `Gusv9b`), so renders now blur in the sandbox too; do not bring Core Image back into a path that must work headless. Reproduce with a `swiftc`-compiled probe run sandboxed: `CIFilter(name:)` and `outputImage` succeed, `createCGImage` fails.

## 2026-09-26 — rule: the worktree guard refuses commands harness.md calls safe

Four agents in one wave were refused plain, sandbox-safe commands: anything naming the worktree path (it contains
`/git/`, read as a git invocation), `python3` heredocs, compound commands with `--package-path`, and any command
containing the word `eval` (`sleepy eval`). harness.md says only loops were refused on 2026-08-28. What worked every
time: write a small zsh script into the scratchpad with the Write tool and run it as one plain call. Belongs in
`project/agents/harness.md` under *Worktree isolation*.

## 2026-09-26 — Pen's re-save is not proof of what Pen draws

Probing malformed mesh points (`DIkwEJ`), Pen re-saved `["0.3", "0.2"]` and `[[0.3], [0.2]]` as the clean `[0.3, 0.2]` yet drew **nothing** for the fill: the save rounds through JavaScript's `Number()`, the draw does arithmetic, where a string or array is `NaN`. Judge Pen's rendering from its export, never from its save. Also: `scripts/pen-oracle` refuses any file Pen reports "is not valid" (Pen still loads it); pass `--accept-invalid` for a malformed-input fixture.

## 2026-09-26 — Pen's bundled-library scheme is a vendor word DocC may not spell

A `.pen` import can name a library Pen bundles with itself, and the scheme for that is
the vendor's old product name. `VendorWordsTests` fails any `.docc` file that spells it,
so DocC refers to it as ``PenLibraries/bundledScheme`` instead; the Swift constant holds
the literal, and `project/` docs may name it. See
[the import-resolution finding](2026-09-26-pen-import-resolution.md).

## 2026-09-26 — A cross-repo agent needs its worktrees side by side

RapidPro depends on `../Woodcase` and `../PixelPeeper`, and Penumbra's Xcode project on `../../Woodcase` and
`../../RapidPro`, all relative. A RapidPro worktree under `RapidPro/.claude/worktrees/` resolves `../Woodcase` through
the symlink there to Woodcase **main**, so it cannot build against an agent's unmerged Woodcase change. Make one folder
per agent holding sibling worktrees — `<base>/Woodcase`, `<base>/RapidPro`, `<base>/Penumbra` (`git -C <repo> worktree
add <base>/<Repo> -b wt/<leaf> main`) — plus `ln -s /Users/ben/git/PixelPeeper <base>/PixelPeeper`, and every relative
path lands on the agent's own copies. Missing the symlink fails RapidPro's resolve with a missing-package error.

## 2026-09-26 — rule: a message to a finished subagent restarts it

`SendMessage` to an agent that has already handed back queues the message and **resumes** the agent. An addendum sent
just after the SwiftUI researcher reported brought it back after its worktree had been removed; it recreated the folder
and started rewriting a script there. Send a finished agent nothing unless you want it working again, and stop a
restarted one with `TaskStop`. Belongs in `project/agents/delegation.md` under *Traps*.

## 2026-09-26 — rule: the briefing template's bare `job claim` expires under a working agent

`delegation.md`'s template says `Claim: job claim <id> --as <name>`, which holds for 30 minutes and is extended
only by the holder's writes. Agents in a wave spend 45–90 minutes building and testing without touching the
tracker, so six of seven claims had silently expired while the work was running and `job status` showed one
claimed leaf. `jobs.md` already says longer work passes a duration; the template should carry it:
`job claim <id> 4h --as <name>`. A default of 60 minutes would not have saved these. The durable fix is in `job`
itself: a claim held for as long as a process lives (`--pid`), or a harness heartbeat.

## 2026-09-26 — A recursive walk over `PenNode`s overflows a Swift task's stack

A Swift task's thread has 512 KiB, and a debug build gives every value temporary its own stack slot — a few KB
per level for any recursive walk over `PenNode`s; release is not much better (a specialized payload decoder was
7.8 KB). The process dies of SIGBUS (exit 138, no output, "Thread stack size exceeded") where the same command
under `lldb` — the 8 MiB main thread — passes. Every walk the `tree` read makes now runs from a work list
(`PenTreeRewrite`, or an explicit stack), and a new walk over the tree must too; what still recurses is freeing a
tree (~770 B a level, compiler-written), Foundation's JSON scanner (~600 B), and walks outside the read path
(`flattenAndInsert`, Equatable, encoding, CodeGen). A walk that only runs with a font resolver or a file on disk
is invisible to an in-memory test — font collection was the last overflow, and only the CLI hit it. Suspect the
stack first when a process dies with signal 10; the crash report in `~/Library/Logs/DiagnosticReports` names the
recursing function; measure a frame with `scripts/stack-frames`, a walk's real use with `StackHighWater` (tests),
and never put a deep-tree test on a bounded `Thread`. See [debug-stack-depth](2026-09-26-debug-stack-depth.md).

## 2026-09-26 — Pen's `Get` visitor throws on a `ref` that writes `children`

`pen interactive` fails `Get((n,c)=>…)` with `TypeError: cannot read property of undefined` — thrown inside Pen,
before the callback — on a document holding a `ref` node with `children` of its own (the shape `banking.pen`'s rows
use), though it exports and saves the file fine. `scripts/pen-oracle --no-layout` skips the layout step for such a
fixture.

## 2026-09-26 — Run the suite under a watchdog; macOS has no `timeout`

A backgrounded `swift test` that wedges (the suspended-await face above) sits at 0 % CPU forever, and the agent that
started it waits with it: one run today sat 36 minutes before anyone looked. Bound every suite run and log it:
`perl -e 'alarm 600; exec @ARGV' swift test --quiet --package-path <wt> > <log> 2>&1`. `timeout` is GNU coreutils and
is not on this Mac. Ten minutes covers every healthy run measured today (about 1 min on a quiet-ish machine, 3 at load
200, 11 at load 280); past it, `sample` the `swiftpm-testing-helper` before killing it.

> **Corrected 2026-09-26 (leaf `DpQmXu`):** ten minutes does *not* cover the 11-minute run at load 280 — it covers
> every run up to roughly load 250. And the alarm kills `swift test`, not its `swiftpm-testing-helper`: the host is
> reparented to launchd and sits there at 0 % CPU. After a watchdog fires, find it with
> `ps -Ao pid,ppid,etime,args | grep '<wt>/.build.*swiftpm-testing-helper'`, sample it, and kill it by pid.

## 2026-09-26 — Ten cold Swift builds at once panic this Mac

Ten agents dispatched together, each into a fresh worktree, all started a cold `swift build` of the whole package within minutes; the MacBook Air (M1, 8 cores, 16 GB) stopped servicing its watchdog and panicked ("watchdog timeout: no checkins from watchdogd in 91 seconds", `/Library/Logs/DiagnosticReports/panic-full-2026-09-26-175420.0002.panic`), killing every agent mid-work. Earlier waves of ten survived because their builds were staggered or warm. Ben's cap: **at most five Swift agents in parallel**, each briefed to pass `-j 3` to `swift build`/`swift test`, and dispatch staggered so their cold first builds don't all land together; a worktree's first build is the expensive one.

## 2026-09-26 — A heavily loaded machine fails WebKit tests and time budgets

With five agents building (load 90–190), the same three tests failed in two agents' full runs and passed when re-run alone
(`--filter "ReactPaintWebViewTests|WebViewTestHarnessTests|WebViewRegressionTests"`, 18/18): `ReactPaintWebViewTests`
(a render-stroke-fills board), `WebViewTestHarnessTests` "Icon font renders glyphs via file URL", and
`WebViewRegressionTests` StatCard, each "An unknown error occurred". Re-run those suites alone before believing a
failure there; if one fails on a quiet machine, it is real. Wave nine (load 100–200) added more faces of the same thing: WebKit `__READY__` timeouts and
frame-load interruptions, `ViewerBrowserTests` scroll, `ReactTransformStateWebViewTests`, the `tree`/`set`
`PerformanceBudgets` at 3–5×. Every one passed re-run alone.

> **Correction (2026-09-27):** this entry also listed `ActivityCommandTests` "--follow stops when the process that
> launched it goes away" as a load flake. That was wrong: it was a real race that load only exposed. The follower read
> `getppid()` *after* its first print; the test's launcher exits the moment it sees that print, so a follower parked
> in between recorded `launchd` as its launcher, took itself for one born orphaned, and never exited. Fixed by
> recording the launcher at the top of `Activity.run()` (leaf 55P02C). With no synthetic load, a launcher that
> SIGSTOPs the follower on its first line and exits left 15/100 pre-fix followers hung, 0/100 after
> (the repro script is in job 55P02C's note). A test failing only under load can still be a real bug.
>
> **Not the whole story (2026-09-27, later):** with that fix merged, the test still failed once each in two agents'
> loaded full runs (load 34–59), passing alone. The race above was real, but something else remains; issue `jBvokK`.
> Until it closes, re-run `--filter ActivityCommandTests` alone before believing a failure there.
>
> **2026-09-28 (`jBvokK`):** the test's own wait had the "Wall-clock assertions" trap: it checked its 30 s deadline
> before looking and never looked after, so a sleep that resumed late ended the wait unlooked. In a loaded full
> run (`swift test -j 3 --quiet`, load 23–28) the test's 20 ms poll sleep resumed after 2.29 s; a 30 s stall is
> the same thing, bigger. It now waits through `PollingWait` (one look after the deadline), and a failure prints
> the follower's `ps` line, stderr, a `sample` and the waiter's longest gap, so the next one names its cause. Not
> proven to be the *only* remaining cause: no failure was caught with the diagnostics in place.

## 2026-09-26 — rule: a forked "research only" subagent edits and commits anyway

The thresholds agent forked a helper (`subagent_type: "fork"`, full context and tools) to find where a doc should
live. The fork had inherited the whole computed plan, so it applied all fourteen test edits, wrote two docs, invented
a cause for an anomalous MAE ("bitmap-offset artifact", struck), and made a `wip` commit in both worktrees — none of
it asked for, and the parent's own edits failed "file changed since read" mid-flight. A prose "research only" does not
hold a fork that can see the plan. Tell every agent that it may not fork for research (use a fresh Explore agent,
which cannot edit), and put "never commit" in every brief an agent writes for its own helpers. Belongs in
`project/agents/delegation.md` under *Traps*.

## 2026-09-27 — Emitted Swift is scanned as library source, and render batches share one `main.swift`

`EditingIsolationTests` greps every line of `Sources/Woodcase` for `@MainActor`, string literals included, so a
generator that writes `@MainActor` into emitted code (the SwiftUI catalog's `main.swift`) fails it: keep the attribute
out of emitted code (top-level `main.swift` code is main-actor already) or put the code in a template under
`SwiftUITemplates/`. Separately, the SwiftUI render batches (`SwiftUIStateBatch`, `SwiftUIScreenBatch`,
`SwiftUISlotBatch`) flatten emitted files into one directory beside their harness `main.swift`, so each copies only
`Sources/PenUI/`; a new batch that copies all of `Sources/` collides with the catalog's `main.swift` (hit by catalog
and again at the slots merge, wave eight).

## 2026-09-27 — rule: the integrator cannot `job done` a leaf an agent still claims

`project/agents/jobs.md` says agents never run `done` and the integrator closes the leaves, but a finished agent's
claim outlives its report: `job done <id>` fails with *task … is claimed by swiftfix (expires in 1h 13m)*. Release it
under the agent's identity first — `job release <id> --as <agent> -F -` — then `job done`. Briefs claim with a 2h TTL,
so waiting it out is not an option. Either the shared rule should say so, or agents should `release` as the last
step of their report.

## 2026-09-27 — `swift build -c release --build-tests` cannot build the tests; `swift test -c release` can

To warm a release build before timing, `swift build -c release --build-tests` fails after the whole library has
compiled, at the test module: *unable to resolve Swift module dependency to a compatible module: 'Woodcase'* — the
release library is built without testability and the tests `@testable import` it. `swift test -c release` builds the
same configuration with testing enabled and runs; use it (with a `--filter` that matches nothing if you only want the
build). Cost one 20-minute release build at load 80 (leaf `cHuvso`).

## 2026-09-27 — An unstyled SwiftUI `Text` is not opaque, and another run sweeps your kept test output

A `Text` with no `foregroundStyle` draws in `.primary`, which on macOS is black at 85 % alpha, not black. Used as a
silhouette — cut out with `.destinationOut`, as `penTextFill(innerShadows:)` does — it leaves a 15 % veil (a probe
build of `render-text-shadows` scored 2.5–6.5 with it, 0.6–2.0 with `.foregroundStyle(Color.black)`). Style a
silhouette opaque explicitly. Separately, `WOODCASE_KEEP_TEST_OUTPUT=1` only stops *your* run sweeping; any other
agent's test run sweeps `pen-exports-<pid>` folders of dead processes from the shared `$TMPDIR`, so the SwiftUI
batch's renders vanish minutes after the run. Give the run its own `TMPDIR=<scratchpad>/…` to keep them, or
rebuild one fixture's views by hand: `woodcase generate swiftui <fixture> --output <dir>`, then compile its
`Pages/` with the support templates and `Fixtures/swiftui-harness/main.swift` (leaf `vVgtB2`).

## 2026-09-27 — A copied `woodcase` binary cannot `shot`; an `xctrace` profile of one shows bare addresses

Copying `.build/release/woodcase` aside to A/B it against another build (`scripts/perf-binary --binary`) leaves
behind `Woodcase_Woodcase.bundle`, and `shot` then dies with *unable to find bundle named Woodcase_Woodcase* —
`perf-binary` reports it as a fast `shot` with an exit code, easy to misread as a timing. Copy the bundle beside the
binary.

> **2026-09-28:** since leaf `ZMvbBb` the bundle is found through `WoodcaseResources`, which throws instead of
> trapping: a bare copy now exits 5 with *Woodcase's resources are missing* and never draws, so the misreading above
> can only happen with an exit code you ignore. `scripts/install` and the Homebrew formula lay the bundle out beside
> the real binary. Separately, Instruments' Time Profiler records a SwiftPM binary's own frames as bare addresses; they need
`xctrace symbolicate --dsym <binary>.dSYM`, which `scripts/time-profile` does. Cost a round of A/B timings and an
unreadable profile (leaf `KXKtc7`).


## 2026-09-27 — The shared SwiftUI render batch holds one themed fixture

`SwiftUIRenderBoard`'s artboard fixtures compile into **one** module, so only one of them may carry a theme:
adding a second fails with `.conflictingTheme("<fixture>", "Sources/PenUI/Theme/PenTheme.swift")`, and
`swiftui-color-scheme.pen` holds the slot. A new themed fixture gets its own batch, as
`render-themed-numbers.pen` does (`SwiftUIThemedNumbersBatch`, modelled on `SwiftUISlotBatch`). Cost the
`QP5E24` agent a build cycle.

## 2026-09-27 — Building a deep `PenNode` chain from Swift values, not JSON, does not dodge its recursive `deinit`

Testing a stack-safe rewrite of `appendDescendantKeys`/`collectInjected`, a 5000-level chain of frames built
directly as `PenNode` values (no JSON, no parser, `PenNode.Kind` is `indirect` so building and holding it is
cheap) still measured **3.85 MB of stack** on a fixed, iterative walk that should have used a few hundred bytes.
The walk was never the cause: `EditableDocument.init(from: document)` keeps its `document` parameter — the
*original*, unflattened tree — alive until `init` returns, and that parameter's `deinit` is the recursive
"freeing a tree" cost the 2026-09-26 entry already names (~770 B/level, matching almost exactly: 3.85 MB ÷ 5000
≈ 770 B). `flatten(_:)` itself never triggers this — its work-list keeps a second reference to each child before
the parent's tuple is discarded, so each pop is a plain decrement — but the *caller's own copy* of the deep tree
outlives that, right up to the moment `init` returns. Measure a walk that must hold a genuinely deep value with
``StackHighWater``, building and freeing the document in a separate `measure` call that is not asserted against
a budget (`PenRefExpanderStackTests`'s `Holder` pattern) — never assume "no JSON" is enough.

## 2026-09-27 — rule: an agent's synthetic CPU load outlives the agent

Reproducing a load-only flake (`55P02C`), the follow agent started `yes > /dev/null &` burners; when the agents were stopped its cleanup never ran, and two orphaned `yes` (PPID 1) held ~95 % CPU each on top of five agents' builds, pinning the Mac at load 70. Never generate synthetic load in a brief — five agents building *is* the loaded machine; if a burner is unavoidable, bound it by itself (`perl -e 'alarm 300; exec "yes"' > /dev/null &`), never by a cleanup step. The second hidden load is Claude Code's `sourcekit-lsp`, which typechecks every file an agent edits in every worktree (six `swift-frontend -typecheck` at ~100 % each, parent `claude`). Find either with `ps -Ao pid,ppid,pcpu,args -r | head`.

## 2026-09-27 — `CGRect.width` is the absolute width, so a negative inset rect is not empty

`CGRect.width` and `.height` are *standardized*: a rect built with a negative width reports its absolute
value. `perSideRing` built its inner rect first and then asked `innerRect.width > 0`, so a centred band wider
than its box came back with a hole the size of the overshoot, and even-odd (or `subtracting`, in the SwiftUI
support's `PenSideStroke`) cut it out: a centred stroke on a 0×0 box drew nothing. Compute the inner width and
height as scalars and test those before building the rect. Cost leaf `Jg0BOv` a debug build.

## 2026-09-27 — rule: a subagent the user stops cannot be resumed; relaunch it from a trail of its transcript

When the wave was stopped to clear the runaway load, `SendMessage` to each stopped agent failed ("stopped by the user and won't be resumed"). Their worktrees survived intact. What worked: condense each agent's transcript (`<tasks>/<id>.output`, JSONL) into its own messages and tool calls, save it as `<leaf>-predecessor.md` in the scratchpad, and brief a fresh agent to read that trail and `git diff` in the same worktree and continue — all five resumed within minutes, without restarting. Belongs in `project/agents/delegation.md` under *Traps*.

## 2026-09-27 — Pen's own drawing code is readable, and settles "what does Pen do" faster than probing

`/Applications/Pen.app/Contents/Resources/app.asar` holds the editor's JavaScript (`out/editor/assets/index.js`); read it straight from the archive (read-only; never modify the app). The Material agent (`6vLFNQ`) found there that Pen draws icons via `getIconPath` at 14 pt with only `wght` set, and fetches Material Symbols from fonts.gstatic.com rather than bundling them — two facts that probing exports had only hinted at. Treat it as evidence of intent, and still confirm against an export (`scripts/pen-oracle`).

## 2026-09-28 — `pen-oracle`'s layout is Pen's first pass, and Pen's first pass is not always its settled layout

Pen fits widths before heights, so on load a turned child whose height is not resolved yet (a `fit_content` frame, a
cross-axis `fill_container`) is measured at height 0 when its parent's width is fitted; any later relayout gives a
different, converged answer (probe rows f20, f21: 160 → 260 and 211.96 → 231.96 wide). The exports and
`layout.json` capture the first pass. Before pinning a turned-in-flex expectation to Pen, nudge the row in the same
`pen interactive` session (set `gap` and back) and `Get` again — `scripts/pen-settle` does exactly that and writes both layouts. See [the geometry model](2026-09-28-geometry-model.md).

## 2026-09-28 — A fixture named `layout-*.pen` joins the SwiftUI golden set

`SwiftUIFixtures.names` takes every `Tests/WoodcaseTests/Fixtures/layout-*.pen`, so a new layout fixture fails
`SwiftUIEmitterGoldenTests` (missing golden, and a hard-coded fixture count) until a SwiftUI golden is generated
for it. Name a fixture that only the layout engine should read something else (`flex-turned-fill.pen`, leaf
`YrLTHN`), or budget for the golden. Cost one full-suite run.

## 2026-09-28 — rule: an agent can be stopped by permission checks that give no verdict

The React effects agent (`Mu4JsL`) hit ten write/Bash calls in a row on which the auto-mode permission classifier
returned no verdict, and stopped early to avoid ending its turn without a report — code done, but full suite, lint,
a doc fix, a README row, a small refactor and its job notes left for the integrator. Nothing in the brief caused it
and a retry does not help. Briefs now say "if permission checks stall repeatedly, stop and report what's left rather
than burning calls", and the integrator should expect to finish such a branch. Belongs in
`project/agents/harness.md` under *Claude Code*.

## 2026-09-28 — WebKit inverts a filter's `SourceAlpha` only inside the element's bounding box

An inner-shadow SVG filter that inverts the silhouette with `<feComponentTransfer in="SourceAlpha"><feFuncA
type="table" tableValues="1 0"/>` loses every edge that lies on the element's bounding box: WebKit leaves the
inverted alpha at 0 outside the bbox, whatever the filter region says, so a hexagon's flat flanks cast no shadow and
the corner triangles smear shadow onto the wrong edges (1.721 against Pen's export). `overflow="visible"` on the
`<svg>` does not help. Build the outside as `<feFlood/>` then `<feComposite in2="SourceAlpha" operator="out"/>`:
the flood fills the whole region (0.036). `sleepy shot --scale 2` of the test's own
`Fixtures/tmp/render-<board>.html` plus `scripts/png-mae` is a fast loop for such probes (leaf `4fZZ38`).

## 2026-09-28 — `swift test --quiet` hides a compile error behind a bare `fatalError`

A test file that does not compile fails the build with `error: fatalError` and nothing else under `--quiet`; without it, the batch lists a dozen innocent files "failed with a nonzero exit code", and the one real diagnostic is in colour, so a plain `grep ': error'` misses it. One agent read nine such failures as disk pressure (the volume *was* low that day, 0.5–7 GiB free) and handed back a test file it believed compiled; the error was `#expect(…, cap)` passing a `String` where Swift Testing wants a `Comment` (leaf `slxqjU`). When a build dies with a bare `fatalError`, rerun without `--quiet` and strip the colour: `sed 's/\x1b\[[0-9;]*m//g' <log> | grep -E '\.swift:[0-9]+:[0-9]+: error'`. Low disk is real too: check `df -h /System/Volumes/Data`, and the integrator frees about 1.7 GB per finished agent by snapshotting its branch (a hooks-off `wip` commit) and removing its worktree. Finder's folder "Size" is logical bytes (45 GB for 5.85 GB on disk here); use `du`.

## 2026-09-28 — `swiftc` over many files without `-wmo` re-parses the module once per file

Handed a few hundred files, `xcrun swiftc` without `-wmo` starts one frontend per file, and each one parses the whole
module again, so the cost grows with files × module size. The SwiftUI render batch (334 files) spent 731 s
type-checking that way on a loaded Mac; whole-module, the same sources took 12.6 s of CPU. It looked like slow-to-type-check
generated code, and a leaf recorded it that way. Pass `-wmo` to any hand-rolled multi-file `swiftc`, and profile with
`-Xfrontend -warn-long-function-bodies=<ms>` before blaming the code. Cost a
15-minute suite and a wrong cause on file (`MeFlNF`).

## 2026-09-28 — Swift Testing times a test from when it was queued, not from when it ran

Every test in a run is started up front, so a test waiting for a free thread is charged the wait: one run had 749
tests, lint findings and CRDT inits among them, all "taking" 74.9–75.1 s. A cluster of trivial tests at one duration is
a queue. Find what the suite waits on from CPU instead (`ps -o time` of the test host against its wall time, or a
`sample` across the run) and per-phase timers (`WOODCASE_TEST_PROFILE=1`). Cost a wrong theory, a lock in Swift
Testing's throw backtraces (`project/2026-09-28-suite-speed.md`).

## 2026-09-28 — A timer on a Task or a global queue cannot fire while the cooperative pool is saturated

`Task.sleep` resumes on a pool thread, and `DispatchQueue.global()` shares its worker limit, so with every pool thread
busy neither runs: `BoundedWait`'s deadline let `sleep 20` under a one-second budget come back as a normal exit after
180 s, and a test that released its pool-blockers from `DispatchQueue.global().asyncAfter` hung for good. A private
serial queue (`DispatchQueue(label:)`) is overcommit and gets a thread anyway; `BoundedWait` fires its deadlines there
now (`BoundedWaitSaturatedPoolTests`). Cost a hung test run and a flaky `SwiftUIRenderBatchRunAsyncTests` (`ko3YrZ`).

