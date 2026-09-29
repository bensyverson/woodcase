# A JavaScript host for the editing loop

*2026-09-07. Vision and implementation plan. Status: proposed; the YAML block at the end is the plan, loaded with `job import`.*

## The premise

Agents write code. Given twelve list rows that differ by one string, or a question like "every text node under 12 pt", a model reaches for a loop before it reaches for a verb. The Quill run produced four Python generators woodcase could not read ([teach the CLI what it does](2026-09-02-teach-the-cli-what-it-does.md)), and the mobile round produced a 50-line parser over `tree --expand` output whose author said afterwards: *"I needed the geometry in a shape a pipe can eat"* ([Quill mobile DX](2026-09-01-quill-mobile-agents-dx.md)).

We answered with what a verb can do — a rule in the primer, `cp --each`, a parked `find`. Those are good answers to the tasks they cover and they stay; they are not answers to control flow, and a rule against writing code fights the instinct. A tool that fights its user's instinct is not ergonomic for that user. The harmful case is not "the agent wrote code"; it is "the agent wrote code that opened the .pen file with `json.load`", skipping the lock, the activity log, undo, id minting and the divergence sentences. That happens because writing code is natural and there is nowhere for that code to go.

So we give it somewhere to go. A `woodcase js` verb runs a JavaScript program inside one file transaction, with a `doc` object whose members are the editing verbs one for one. The program can read, decide and write atomically, which no batch can. JavaScriptCore is the engine: it ships as a system framework on every platform we build for, it has no filesystem or network by default, and models are more fluent in JavaScript than in any grammar we could teach.

This is the "correct path" the principles ask for. Every fence we would otherwise build is a band-aid over the same missing surface.

## What ships

```text
$ cat rows.js
const section = doc.get('banking-home/transactions-section');
const template = doc.tree('banking-home/transactions-section')
  .filter(r => r.type === 'ref' && r.depth === 1)[0];

for (const [i, name] of ['Groceries', 'Transit', 'Coffee'].entries()) {
  doc.cp(template.id, section.node.id, {
    props: {
      'common.name': `row-${name}`,
      'info/merchant/kind.content': name,
      'amount-wrap/amount/kind.content': `$${(i + 1) * 4}.00`
    }
  });
}

const tall = doc.tree('banking-home/transactions-section')
  .filter(r => r.depth === 1 && r.rect.height > 64);
if (tall.length) throw new Error(`${tall.length} rows overflow: ${tall.map(r => r.address).join(', ')}`);

doc.rm(template.id);
doc.lint().length

$ woodcase js banking.pen -F rows.js --as ana
cp           banking-home/transactions-section/row-Groceries  lBqEd
cp           banking-home/transactions-section/row-Transit  2yL6J
cp           banking-home/transactions-section/row-Coffee  YGWHA
rm           banking-home/transactions-section/t1  aqCub
result  45
document  9e08ac2781a9d195
```

> **Corrected 2026-09-07, as `js` shipped (leaf DESilx).** The transcript first written
> here could not run. `banking.pen` has no `banking-home/recent` — the list is
> `banking-home/transactions-section`, and its rows are `ref` instances of
> `component/TransactionItem`, not frames; a `TreeRow`'s member is `address`, not `path`;
> `doc.get` answers a `NodeReport`, so the parent id is `section.node.id`; and `cp` has no
> `name` option — a copy's name is `props: { 'common.name': … }`, the same prefixed-path
> vocabulary `set` takes, and a key written as a *path* into the copy
> (`info/merchant/kind.content`) becomes an override, which is what fills an instance's
> text. The measurement needed `r.depth === 1` too: the un-filtered `tree` read includes
> the section itself, which is taller than any row and would have thrown every time. The
> run above is the real one, against `Tests/WoodcaseTests/Fixtures/banking.pen`, and
> `JsCommandTests.planTranscriptRuns` is that script as a test. Two things it shows that
> the sketch did not. **Rows carried no verb column** when `js` first shipped:
> `ScriptRun.Event.write` held a `WriteReport` and nothing that says which member made it,
> so a row was the path, the id and `(+N)` — corrected by the block below. **The ids and
> the revision change every run**: `cp` mints fresh ids, and the revision is a fold over
> them. `result 45` is `doc.lint().length` on the real fixture, which lints dirty on its own.

> **Corrected 2026-09-07, as `help js` shipped (leaf HNG9g4).** The verb column landed:
> `ScriptRun.Event.write` now carries a `ScriptWriteMember` beside the report, and a
> transcript row is `<member>  <path>  <id>  (+N)` with the member padded to the widest
> name any run could print — `apply`'s fixed status column, one surface over. The
> transcript above is that run, re-run for real; a document-level write (`vars.set brand`)
> is `<member>  <name>`, and `--json` events carry `member`. The reason is the one the
> `js` leaf gave: `doc.override` reports the *instance*, so a `cp` and the three overrides
> that fill the copy printed four rows nobody could tell apart.

One transaction, one revision. The rows were copied, filled, measured after layout settled, and the template removed — or, had a row overflowed, nothing at all was written and the message named the rows. The script is the policy: a `try` around a write continues past it, an uncaught error rolls the whole run back.

`woodcase help js` prints a TypeScript declaration of `doc` and a primer whose every snippet runs.

The same host gives the pure-CLI route its query verb. `find` takes a JavaScript predicate over tree rows, with no grammar of its own to learn:

```text
$ woodcase find banking.pen 'r => r.type === "text" && r.props["kind.fontSize"] < 13' --props kind.fontSize
rev dca344725f21de2d  3 rows
type  name      rect             clip       id     kind.fontSize
text    label   0,8 30×14                   M5gJu  12
text      date  0,19 88×14       ⚠ clipped  EUsYj  12
text    label   -14.50,26 29×13  ⚠ partial  HpvPY  10
```

> **Corrected 2026-09-07, as `find` shipped (leaf Dy6k8Z).** The transcript first written
> here showed a bare listing whose second column was each row's *path*. That is not a form
> `tree` prints, and `find`'s contract — one sentence below this block — is `tree`'s own
> format and `--json` shape, so that the two pipe into the same things. The run above is
> the real one, against `Tests/WoodcaseTests/Fixtures/banking.pen`: `tree`'s header
> carrying the revision, `tree`'s columns, the name indented by depth, and the id last as
> the address a later verb takes. The shape of the question is unchanged.

### Two routes, on purpose

An agent gets to choose between the verbs and a program, and both routes are taught. `cp --each` stays as the fan-out that needs no program; `apply` stays as the multi-edit transaction that needs no program; `find` is the query that needs no script. `js` is where control flow lives: read, decide, write, in one transaction. Whether any of the verb-side surfaces is redundant is a question the agent trial at the end of the plan answers with data, not one this doc decides by symmetry.

## The contract

### Verb

```text
woodcase js <file> -F <script.js> [-F <more.js>…] [--as <name>] [--guard <pin>…] [--dry-run] [--json] [--timeout <seconds>]
```

`-F -` reads the script from standard input, as every body does. `-F` repeats: the files are evaluated in order in one context, so a helpers file precedes the run that uses it (see *No session*, below). The flags are `apply`'s: identity, entry guards, dry run, JSON output. `--timeout` bounds the run (default 30 s). No `--atomic`: the script decides what to catch.

### find

```text
woodcase find <file> [<address>] <predicate> [--expand] [--props <list>|--props] [--absolute] [--json]
```

A read verb over the host: it settles the tree once, evaluates the predicate — a JavaScript arrow function receiving one `TreeRow` — against every row under `address` (the whole file when omitted), and prints the rows that answer truthy in `tree`'s own format and `--json` shape. `--props` adds the named properties to each row as `r.props['kind.fontSize']`, exactly as `tree --props` does. Exit `0` with matches, `1` for none (the clean negative, so `find … && …` branches), `2` when the predicate does not parse or throws — naming the row it threw on and the property names a row carries, since `r.fontSize` is the mistake a model makes. The predicate may also be given with `-F` when it outgrows a line. A predicate has no `doc` and cannot write.

> **As built, 2026-09-07 (leaf Dy6k8Z).** Two details this paragraph left open, decided in the code. **`r.props` is a view, not the row's own key**: a `TreeRow` encodes its columns under `properties`, which is what `tree --json`, `find --json` and `doc.tree()` all print. `r.props` is the shorthand this paragraph promised; both spellings reach one guarded view, so a path `--props` never asked for is refused either way rather than read as `undefined`. **The refusal is a `Proxy` trap, as the plan's own `doc` object is**: `r.fontSize` is `undefined` on a plain object and `undefined < 12` is `false`, so a plain row would answer "no matches" to a question nobody asked — the worst thing a query tool can do. Every row a predicate sees is a `Proxy` that refuses a member the row type does not have and lists the ones it does; `doc` is a global getter that throws the sentence naming `js`. See `Sources/WoodcaseScripting/Predicate/RowPredicatePrelude.swift`.

**stdout** is the answer: one row per write as it happens (the verb, the path, the id, `(+N)` for created children, divergences indented under the row exactly as a batch prints them), the `console.log` lines interleaved where the script printed them, the script's completion value as `result`, and the document revision last. **stderr** carries only what stderr carries today: warnings and refusals. With `--json` the whole run is one object — `writes`, `log`, `result`, `documentRevision`, `error` — built from the same typed values the text is.

Exit codes are the house table. An uncaught script error is `1`: the check ran and the answer is no, the file is untouched. A stale guard is `3`. A script that does not parse is `2`, with the line and the message. The timeout is `3`, a budget ran out.

> **Corrected 2026-09-07, as `js` shipped (leaf DESilx).** Two things above are not what
> was built. **A write row carried no verb** — `ScriptRun.Event.write` held a
> `WriteReport` and nothing that says which member made it, so a row was the path, the id
> and `(+N)`; leaf HNG9g4 added the field, and the column is there now. **`--json` carries
> `events`, not `writes` and `log`** — one timeline, which is what the paragraph two
> sections down argues for and what `ScriptRun` actually holds — alongside `result`,
> `documentRevision`, `commit`, `error`, `warnings`, and `dryRun` plus `lint` for a
> rehearsal. Two exit codes the paragraph left open, decided against the code rather
> than by symmetry: a `-F` path that cannot be *read* is `4`, because `InputFile`'s
> contract is that a body which cannot be read is a target failure and that is what
> `apply -F missing` already does; and a run that ended in an error, like a rehearsal,
> names no revision, because neither made one. The shipped contract is the `js`
> section of `Sources/Woodcase/Documentation.docc/WoodcaseCLI.md`.

### The `doc` object

The API mirrors the verbs one for one, with the same names, so the primer teaches both at once and a model that knows one knows the other. Options are the verb's flags, camel-cased. The sketch below is the contract the first leaf refines into the shipped `.d.ts`:

```ts
/** The open document. One transaction: nothing is written until the script ends
 *  without an uncaught error. Every read after a write sees settled layout. */
declare const doc: {
  /** The document revision, live — it changes after every write. */
  readonly rev: string;

  // ── Reading ──────────────────────────────────────────────────────────
  /** One row per node under `address` (the whole file when omitted), as
   *  `woodcase tree --json` prints: type, name, path, id, rev, depth, rect. */
  tree(address?: string, options?: { depth?: number; expand?: boolean; props?: string[] | true; absolute?: boolean; theme?: string[] }): TreeRow[];
  /** One node as the file stores it, with its revision — `woodcase get --json`. */
  get(address: string, options?: { props?: string[] }): NodeReport;
  /** What is wrong with the document as it stands now — `woodcase lint --json`. */
  lint(options?: { check?: string[] }): LintFinding[];
  /** The property table for a node type, or the overview — `woodcase schema --json`. */
  schema(type?: string): object;

  // ── Writing ──────────────────────────────────────────────────────────
  // Each call is applied whole or throws; a caught throw leaves the document as it was before the call.
  set(address: string, props: Props, options?: { rev?: string }): WriteResult;
  add(parent: string | null, node: PenNode, options?: { at?: number; rev?: string }): WriteResult;
  replace(address: string, node: PenNode, options?: { rev?: string }): WriteResult;
  cp(address: string, parent: string, options?: { at?: number; name?: string; props?: Props; rev?: string }): WriteResult;
  mv(address: string, parent: string, options?: { at?: number; rev?: string }): WriteResult;
  rm(address: string, options?: { detach?: boolean; rev?: string }): WriteResult;
  override(instance: string, descendant: string | null, props: Props, options?: { unset?: string[]; rev?: string }): WriteResult;
  vars: {
    set(name: string, value: PenVariable): void;
    rm(name: string, options?: { force?: boolean }): void;
  };
  themes: {
    set(axis: string, options: string[]): void;
    rm(axis: string): void;
  };
  imports: {
    set(alias: string, path: string): void;
    rm(alias: string): void;
  };
};

/** What a write says back — the same fields the terminal's three lines are built from. */
interface WriteResult {
  id: string; path: string; rev: string;
  created: CreatedNode[];           // add and cp: the subtree that came into being, ids included
  divergences: Divergence[];        // what was stored means something other than the plain reading
  node: PenNode;                    // the stored form, children stripped
}

/** Thrown by any member. `code` is the error family; `candidates` is the copy-paste fix when there is one. */
declare class WoodcaseError extends Error {
  code: 'ambiguousAddress' | 'addressNotFound' | 'revisionConflict' | 'unknownProperty' | 'propertyTypeMismatch' | 'overrideTargetNotFound' | 'componentHasInstances' | /* … every EditingError case … */ string;
  candidates?: { id: string; path: string }[];
}
```

Things the sketch settles on purpose:

- **No batch tags.** A `@tag` exists so a later JSONL line can name what an earlier one created; in a program the return value carries the id. `const hero = doc.add(…); doc.set(hero.id, …)`.
- **No selector language.** `doc.tree()` returns rows with settled rects; JavaScript's own `filter` is the selector, and `find` is that filter as a verb. This un-parks `find` without the second address grammar the backlog records nobody wanting.
- **`Props` is the prefixed-path vocabulary** (`common.name`, `kind.content`), exactly as `set` takes it, with the same `$variable` and `\$` rules. A node passed to `add` or `replace` is plain .pen JSON, ids optional, as `-F` takes it.
- **Return values are the report types**, not summaries of them: `CreatedNode`, `WriteDivergence`, `LintFinding` and the tree rows are already public `Codable` values in the library. Text and script data cannot drift because both are pure functions of the same value.
- **Writes are the batch planner's writes.** Every member routes through `BatchApplier.applyOne` with the transaction's `ActivityRecorder`, so the activity log, undo, divergence detection, root-overlap warnings and per-call revision checks are the ones the verbs already have. The host adds no editing semantics of its own; an adapter that held one would be a bug.

### Transaction semantics

The run is one `PenFileTransaction.run(at:identity:log:effect:)`, the same door every write verb uses. Entry guards are checked first, then the script runs on the caller's isolation with the document (see *Un-pinning the editing layer*), then the transaction encodes, compares and renames as it always does. Three consequences the primer states outright:

- **Nothing is written until the script ends.** An uncaught error, a timeout or a kill leaves the file byte for byte what it was, and the advisory `flock` dies with the process. There is no partial commit to reason about.
- **Each call is atomic on its own.** `applyOne` validates before it mutates, so a thrown call has changed nothing, and a script that catches it continues from a consistent document. This is a tested invariant, not a hope.
- **The log records what the script did**, one event per write, in order, under one batch id — indistinguishable from the same edits made by hand. `undo` reverses the whole run as one step, as it does a batch — a behavior this plan adds, since today `undo` walks one event at a time (see *Review of 2026-09-07*).

`--dry-run` runs everything and writes nothing, with `lint` findings on the resulting document, as `apply --dry-run` does today.

### Reads see settled layout

Pen's own MCP taught us the rule ([tire-kick](2026-08-29-pen-mcp-tire-kick.md)): *a read after a write must see settled layout, in the same invocation, always.* The host keeps one `SettledTree`, built on the first read and dropped on every write. A script that alternates a write and a read a thousand times settles a thousand times; `SettledTree` is a full pipeline by design, so this is the one place the host can be slow. The plan measures it on the 1,850-node design-system file and records the figure in `WoodcasePerformance.md`; incremental settling behind the same cache is the optimization if the figure demands it, and it changes no contract.

### Errors that teach

The verbs' strength is that a refusal carries its own fix. The host must not trade that for a stack trace:

- **Every error thrown into the script is a `WoodcaseError`** with the same sentence the verb prints — the remedy dialect, the candidate list on an ambiguous address, the near misses on a missing one — plus a `code` and, where the sentence lists candidates, a `candidates` array the script can act on without parsing prose.
- **An uncaught error is reported with its script location**: the line and column JavaScriptCore records, the source line quoted, then the sentence. The report says plainly that nothing was written.
- **Contextual help on the mistakes a model actually makes.** `doc` is a JavaScript `Proxy`: `doc.setProps(…)` throws *"doc has no setProps — its members are set, add, replace, cp, mv, rm, override, tree, get, lint, schema, vars, themes; woodcase help js prints them"* instead of `TypeError: not a function`. An unknown option key (`{ position: 0 }`) is refused naming the keys that member takes. A `props` that is not an object, a node without a `type`, an `at` past the end — each gets the sentence the verb already has for it.
- **`help js` is executable.** The primer's snippets run under the same extraction test that runs every recipe, and a reflection test checks that every member the `Proxy` exposes appears in the `.d.ts` and nothing in the `.d.ts` is missing at runtime.

The `Proxy` and the option validation live in a JavaScript prelude the host evaluates before the script, stored as a Swift string the way the viewer's script is.

### Runaway scripts

The public JavaScriptCore headers on macOS 15 carry no execution-time limit and no interrupt (checked 2026-09-07: `grep -ri 'TimeLimit\|Interrupt' $(xcrun --show-sdk-path)/System/Library/Frameworks/JavaScriptCore.framework/Headers` finds only license text). So the budget is enforced in two layers:

1. **Every bridged call checks the clock.** A script past its deadline gets a `WoodcaseError` (`code: 'timeout'`) on its next `doc.*` call, which it can catch. This covers every script that does work, and it is the whole of what the library host does.
2. **The CLI adds a watchdog thread that ends the process** at `--timeout` plus a short grace, printing *"script ran past N s; nothing was written"* on stderr and exiting `3`. This covers the pure `while (true) {}` that never calls back into Swift. It is safe because of the transaction's shape: no bytes are written before the body returns and the lock is the kernel's to release. It is the CLI's layer and never the library's.

The watchdog test asserts the outcome — the message, the exit code, the untouched file — not the elapsed time; wall-clock assertions are unreliable in the parallel suite (`project/gotchas.md`, 2026-08-29).

### What a run says back

The host returns one `ScriptRun`: an ordered timeline of events, the completion value, the revision and how the transaction ended. One timeline rather than separate arrays, because what was printed before which write is part of the answer.

```swift
public struct ScriptRun: Friendly {
    public enum Event: Friendly {
        case write(WriteResult)                 // the verb's own echo: id, path, rev, created, divergences, stored node
        case log(level: LogLevel, text: String) // console.log / warn / error
        case warning(String)                    // root overlap and friends, as the verbs print them
    }
    public let events: [Event]
    public let result: JSONValue?               // completion value of the last source, JSON-encoded
    public let documentRevision: String
    public let commit: Commit                   // wrote, unchanged, previewed, rolledBack
    public let error: ScriptError?              // source name, line, column, quoted line, code, candidates
}
```

**The read-back on a write is the `WriteResult`**: the stored node and the created subtree with ids, exactly what the verb prints. It carries no settled rect, on purpose: a write invalidates layout, and a rect per write would force a settle per write. Geometry is asked for through `doc.tree` when the script wants it.

**The general read-back is the return value.** A script that wants to hand its caller a structured answer composes one as its last expression — `({ rows: doc.tree('list'), lint: doc.lint() })` — and the completion value of the last source is the result. No wrapping function and no top-level `return`, so a one-liner from stdin works unchanged. The value crosses through `JSON.stringify` in the script's own context; a function, a symbol or a cycle cannot, so the result is null with a warning event saying so, never a silent `[object Object]`.

**`console` follows the conventions a model expects**: several arguments joined by spaces, objects rendered as JSON, and `warn` and `error` carrying their level. The CLI prints log lines to stdout interleaved with the write rows, sends warn and error lines to stderr, and keeps them all in order under `--json`.

**Events stream.** The host takes an optional sink closure called synchronously per event and still returns the whole run at the end. The CLI's live transcript is that sink writing to stdout; a library caller that wants an `AsyncStream` builds one from the closure in a line.

**The report vocabulary moves into the library.** `WriteReport` and `NodeReport` are internal to the command core today, so a library caller cannot get a write's echo or a `get` result as a value, and the host could not return them without a twin. They move next to `BatchReport` in `Woodcase`, as the one struct every caller imports; the CLI formats them and holds nothing of its own. The same goes for undo: the step logic and replay live in the command core, so a library caller has the log but no way to reverse an edit from it. They move with the revision-lineage extraction the out-of-band leaf already makes.

### Un-pinning the editing layer

`EditableDocument` is `@MainActor`, and by contagion so are nineteen library files: the batch planner, the caches, the recorder, the transaction, the linter, the settled tree, the tree view, the CRDT document and the renderer. The pin is a Penumbra-era decision ([editing architecture, 2026-04-01](2026-04-01-editing-architecture.md)); its reasons were that all mutation came from UI events, that `@Observable` wanted it, and that it bought compile-time safety without `await`. None holds as a library reason today: the CLI, batches, remote CRDT operations and scripts all mutate the document from nowhere near a UI; observation does not require actor isolation; and a non-isolated, non-`Sendable` class gives the same compile-time guarantee more flexibly — the compiler refuses to let it cross an isolation boundary, so whoever creates it owns it, on whatever actor they chose. Penumbra itself fights the pin with a `nonisolated(unsafe)` holder, and the test suite pays for it in main-actor saturation (`project/gotchas.md`, 2026-08-29).

So the plan un-pins first, before the host exists. The document and everything pinned by contagion become non-isolated and non-`Sendable`; the transaction's body takes an isolated parameter defaulting to the caller's isolation instead of hopping to the main actor. The CLI still runs on main because its entry point is main, Penumbra keeps its copy on main because its view model is, and a test or a script runner runs wherever it calls from. Nobody annotates anything at a call site. The host is then written isolation-agnostic from day one, which is what lets a library caller run a script off the main thread and what lets the watchdog be a *deadline* rather than a process exit.

**The watchdog is CLI policy, not library behavior.** The library host exposes a deadline that bridged calls check and throw on, and nothing more; a host that called `exit` inside Penumbra would kill the editor. The CLI installs the process-ending watchdog on top of the deadline. A library consumer that needs a hard bound on a pure loop runs the host out of process.

### Platform

JavaScriptCore is a framework on macOS and iOS, absent on Linux. The host lives in a new library target, `WoodcaseScripting`, that depends on `Woodcase` and imports JavaScriptCore behind `#if canImport(JavaScriptCore)` — the same posture `WoodcaseViewer` takes for Network.framework: always declared, compiling no sources elsewhere. The package already declares macOS 15 and iOS 18 only, so today this costs nothing; the target boundary keeps the Apple dependency out of `Woodcase` itself, and makes the host consumable by Penumbra, which hosts Pen's MCP and whose `execute` is exactly this shape.

The bridging shape was spiked on 2026-09-07 outside the repo: `@convention(block)` closures installed with `setObject(_:forKeyedSubscript:)`, a `JSValue(newErrorFromMessage:in:)` assigned to `context.exception` to throw, and the whole run synchronous inside one function so the non-`Sendable` `JSContext` never crosses an isolation boundary. It compiles clean under `-swift-version 6 -strict-concurrency=complete`, Swift-thrown errors are catchable in the script, and uncaught ones reach `exceptionHandler`. No `JSExport` and no `NSObject` subclasses are needed.

## Out-of-band writes

Even with a good host, some agent will open the file in Python once, and Pen.app writes the file without asking for the lock. Today the CLI notices only in `undo`, as `blockedByStale`. The check should be a property of every write.

The mechanism exists: every `ActivityEvent` carries the document revision *after* its operation, and `documentRevision` is a Merkle fold over the parsed model, so *newest event's revision equals the parsed file's revision* proves the last writer was woodcase and nothing has touched the file since. `UndoStep.decide` already implements the comparison and the scan back through undo events.

The plan:

- **Extract the comparison** from `UndoStep` into a library type both share, so there is one implementation of "does the log explain this file".
- **Check at every logged transaction's entry**, right after the parse and before the body. A mismatch prints a note on stdout — *"note  banking.pen was rewritten outside woodcase since rev 9c1b04e6 (ana, 10:32); the log has no record of that change"* — and continues. It is a note and not a refusal because the edit may be legitimate: Pen.app saved.
- **Record it.** The transaction appends an `external` event first — identity unattributed, no inverse, the revision the file was found at. From then on the invariant holds: *the newest event's revision equals the file's revision at the moment any woodcase write begins.* The note fires once, not on every subsequent write, and `activity` shows when the outside edit happened.
- **`undo` stops there.** An `external` event has no inverse; `undo` reaching one refuses with *"cannot undo past an edit made outside woodcase at 10:32"*. This also removes the one heuristic `UndoStep` documents: with outside edits recorded, a revision mismatch during the scan is no longer ambiguous between "undone earlier" and "edited outside", because the second case now has a row.

This leaf is independent of the host and can be built in parallel with it.

### No session

A run is a process holding a file lock, and nothing survives it: no globals, no functions defined last time. The distinction that keeps this from being a limitation is **code versus state**. Durable *state* is the wrong promise: a persistent context means a daemon (parked, with conditions this does not meet), closures cannot be serialized, and hidden state breaks the read–write–verify loop — what a script did would depend on what an earlier script defined, invisible to a fresh agent, to the same agent after compaction, and to a second agent on the same file. Pen's MCP taught this already: do not promise session state you cannot keep. Everything worth carrying over is recoverable from the file (ids are in the tree) and the log (history).

Durable *code* is a file. `-F` repeats, so `woodcase js design.pen -F helpers.js -F run.js` evaluates the helpers first, in the same context; the helpers live in the repo, visible, versionable, and every run reproduces from its command line. Nothing is auto-loaded from a conventional path — an implicit prelude is hidden state by another door.

### Scripts are sources, not paths

The library takes an ordered list of `ScriptSource` values, each `.file(URL)` or `.text(String, name:)`, and evaluates them in order in one context. The CLI's repeated `-F` maps onto that list and nothing more; `find`'s predicate is one `.text` source. A consumer of the library — Penumbra, a test — hands the host strings it already holds without touching disk, and an error's reported location names the source it came from, the file's path or the name given to the string. This is the library-plus-thin-executable rule applied to the script itself: the decision of where a script comes from belongs to the caller, so the host holds none.

## What this may retire

Nothing, until the trial reports. `apply` is the pure-CLI multi-edit transaction and `cp --each` the pure-CLI fan-out; a program subsumes both, but an agent that would rather not write a program is the reason they exist. The last leaf runs an agent against a real task with every route available and records which it reached for. If a surface goes unused and the primer is simpler without it, a leaf retires it then, with that evidence as its note. `BatchApplier` stays in any case: it is the planner the host and the verbs share.

Stage is BUILD; nothing depends on the JSONL form outside this repo (checked 2026-09-07: RapidPro and Penumbra import none of the editing types), so a retirement, if it comes, costs only this repo.

## Non-goals, and what stays parked

- **No `require`, no I/O, no network.** The script sees `doc`, `console` and the language. A script that needs a file's contents has it passed in by the caller's shell.
- **No selector grammar, no `arrange`, no parameter language.** Each stays parked; a `find` predicate and a `for` loop are the answer the backlog was waiting for.
- **No jq inside `find`.** The jq route is `tree --json | jq`, and it stays exactly that; a verb that shells out to an installed binary makes that binary a dependency.
- **No daemon.** A run is a process; the backlog's conditions for a warm host are unchanged.
- **Linux.** Not a target today; if it becomes one, QuickJS as a C target is the fallback and a real dependency to ask about.

## Review of 2026-09-07

Checked against the code before import; each item carries its ruling, and the leaves below absorb them.

- **Undo by transaction.** `undo` walks events one at a time; the batch id is recorded on every event but nothing reads it, so a forty-write run is forty undos. *Ruled:* `undo` reverses the most recent transaction by default and `-n` counts transactions, since that is what undo means to a person; `--event` keeps the per-event form. A behavior change, owned by the out-of-band leaf with undo's move into the library.
- **The command core is one flat folder** of a hundred files, with ninety tests beside it, against the rule that sources are grouped one level deep. *Ruled:* a pure rename leaf first, before any fan-out touches those files: `Verbs/`, `Options/`, `Reports/`, `Failures/`, `Help/`, `Shot/`, `Lookup/`, `Hosting/`, and the test folder mirroring it.
- **The host-core leaf was too big.** *Ruled:* the report-vocabulary move is its own leaf, after the rename and in parallel with the un-pin.
- **Penumbra consumes Woodcase by local path** (`../../Woodcase` in its project), so the un-pin breaks Penumbra's build the moment it lands on `main`. The un-pin leaf lands the Penumbra changes in the same sitting and names that commit in its report.
- **No event loop.** JavaScriptCore runs a script to completion with no timers and no I/O: `setTimeout`, `fetch`, `require`, `import` and top-level `await` are the mistakes a model makes on day one. The prelude defines each to throw a sentence saying scripts are synchronous and why; an `async` function's Promise as the completion value gets the null-plus-warning treatment.
- **Per-source line numbers.** Sources are evaluated one at a time with their own source URL, so an error in the second `-F` file reports that file's line, not a line in a concatenation. Top-level `let` and `const` are shared across sources in one context, so a helper file and a run file redeclaring the same name is a syntax error; the primer says so.
- **Typed values, not argv text.** A script's values arrive typed, the way JSONL values do: the argv coercion rules (`'"42"'`, the number-to-text bending) do not apply, `$name` strings stay strings, and an integer written from JavaScript is stored as an integer, not `10.0`, because marshaling goes through JSON text. The revision depends on this.
- **A library run needs no log.** `BatchApplier.applyOne` takes an optional recorder, so a library caller can run a script over an in-memory document with no activity log; the write leaf carries it as a criterion.
- **Memory is unbounded.** JavaScriptCore has no public memory limit either. The CLI's watchdog bounds time only; a script that allocates without end is the operating system's to kill. Accepted, stated.
- **No `doc.shot()`.** A script sees geometry, not pixels; `shot` is a verb the shell runs after. Consistent with the loop needing no pixels.

## Verification

The premise is a claim about agent behavior, so the plan ends by testing it, not by shipping it. The last leaf runs a Sonnet-class agent against a real task of the Quill shape — a list, a fan-out, a measurement, a fix — with the primers as its only teaching and every route available, and records which it reached for: `cp --each`, `apply`, `find`, `js`, or something outside the tool. The finding lands as a dated doc. The plan is done when an agent given a loop-shaped task stays inside the tool, and the activity log accounts for every byte the file changed by.

## Plan

```yaml
tasks:
  - title: A JavaScript host for the editing loop
    ref: host
    labels: [scripting]
    desc: |
      Vision, contract and rationale in project/2026-09-07-scripting-host.md; read it first.
      A `woodcase js` verb runs a JavaScript program inside one file transaction against a
      `doc` object whose members mirror the editing verbs one for one, returning the same
      typed reports the verbs print. JavaScriptCore is the engine; the host is a new
      library target so Penumbra can consume it. Out-of-band write detection ships
      alongside because it is the same premise from the other side: every byte the file
      changes by is accounted for in the activity log.

      Strict TDD throughout: every leaf begins with failing tests. CLI tests spawn the real
      binary through CommandFixture (Tests/WoodcaseCommandTests/Support/CommandFixture.swift), which
      isolates the activity log with WOODCASE_HOME; library tests get their own target.
      The Swift toolchain fails inside the Bash sandbox; see project/agents/harness.md.
    children:
      - title: Group the command core into folders
        ref: layout
        labels: [scripting, tidiness]
        desc: |
          Sources/WoodcaseCommandCore is a hundred files in one folder and
          Tests/WoodcaseCommandTests ninety, against the rule that sources and tests are grouped
          in folders at most one level deep. A pure `git mv`, no content change, done first so
          no fan-out branch has to merge across renames:

          - Verbs/ — every *Command.swift, WoodcaseCommand.swift, WoodcaseVersion.swift
          - Options/ — AddressArgument, BareOptionValue, DryRunOption, GuardOption,
            IdentityOptions, IdentityRole, InputFile, LintCheck+Argument, OutputFormat,
            OutputOptions, PenDiagnosticSeverity+Argument, PenFilePath, PenInputPath,
            PenVariableType+Argument, PositionOption, PropertyAssignment, RevisionOption,
            ThemeOption, ThemePinParser, ThemeCombination, VariableAssignment, VariableTyping
          - Reports/ — WriteReport, NodeReport, NewFileReport, UndoReport, InstanceReport and
            every *Formatter, RootOverlapWarnings, CanonicalJSON, Schema*JSON
          - Failures/ — CommandFailure, ExitCode+House, ParsableCommand+Failures,
            ParserFailureMessage, SandboxDenial, StandardError, UndoFailures
          - Help/ — HelpTopic and its extensions, SchemaHelp
          - Shot/ — Shot*, ImageExporter, OutputNamer
          - Lookup/ — NodeLookup, InstanceLookup, LibraryResolver, UndoStep, VariableValueEditor
          - Hosting/ — ViewerHosting, ParentProcessWatch

          Tests mirror the same folders by the type they test. SwiftPM needs no manifest change
          for subfolders. Any file that resists a group is a sign it wants splitting; note it
          rather than forcing it. A Sonnet leaf; the integrator can also do it directly.
        criteria:
          - No Swift file sits directly in Sources/WoodcaseCommandCore or Tests/WoodcaseCommandTests, and every folder is one level deep
          - git shows every move as a rename with no content change, and the full suite passes unchanged
      - title: Move the report vocabulary into the library
        ref: reports
        labels: [scripting]
        blockedBy: [layout]
        desc: |
          WriteReport, NodeReport and CreatedTreeFormatter's Report are internal to
          WoodcaseCommandCore, so a library caller cannot get a write's echo or a `get` result
          as a value and the host could not return them without a twin. Move them into
          Sources/Woodcase/Batch/ as public Friendly types beside BatchReport; the command
          core's Reports/ keeps only the text formatting, as pure functions of those values.
          Name the write echo once — WriteReport is the name; the plan doc's `WriteResult` is
          it. Touches the command core's formatters and none of the un-pin's files, so it runs
          in parallel with unpin.
        criteria:
          - WriteReport, NodeReport and the created-tree report are public library types with DocC, and the CLI's text and JSON for them are byte-for-byte unchanged under the existing tests
      - title: Un-pin the editing layer from the main actor
        ref: unpin
        labels: [scripting, concurrency]
        desc: |
          Remove `@MainActor` from EditableDocument and everything pinned by contagion —
          nineteen files in Sources/Woodcase: BatchApplier and its helpers (BatchErrorMessage,
          BatchPoison, CopyAssignment), the three caches (Expansion, Layout, Revision),
          RootOverlap, EditableDocument+StateTransfer, ActivityRecorder, LintPreview,
          PenFileTransaction, DocumentLinter, PenRenderer, CRDTDocument, CRDTSnapshot,
          SettledTree, TreeView. The types become non-isolated and non-Sendable: whoever creates
          a document owns it on the actor of their choosing, and the compiler still refuses to
          let it cross a boundary. PenFileTransaction's bodies take
          `isolation: isolated (any Actor)? = #isolation` and run on the caller's isolation
          instead of `MainActor.run`; the CLI still lands on main because its entry point is.
          Two spots need thought rather than deletion: `onRemoteChange` and the CRDT peers, whose
          operations are Sendable values crossing to wherever the peer lives, and the caches,
          which stay owned by the document. Keep `@Observable`. `nonisolated(unsafe)` is not an
          answer anywhere in the library. Rationale and the superseded April reasoning:
          project/2026-09-07-scripting-host.md, "Un-pinning the editing layer".

          This is fail-closed concurrency work: an Opus leaf. Penumbra
          (/Users/ben/git/Penumbra, 26 app files hold the document) consumes Woodcase by local
          path (`../../Woodcase`), so this breaks its build the moment it lands on main: land
          the Penumbra changes in the same sitting, with its `nonisolated(unsafe) var
          _editableDocument` workaround in PenumbraDocument.swift deleted, not kept, and name
          the Penumbra commit in the report. RapidPro imports none of these types.
          Run the loaded soak afterwards (scripts/soak-tests, --load 6) — the suite's
          main-actor saturation should ease, and any new flake is this leaf's.
        criteria:
          - No @MainActor remains in Sources/Woodcase, proven by a grep test, and the package builds under Swift 6 strict concurrency with no warnings
          - A transaction body runs on the caller's isolation, proven by a test that runs one from a non-main actor
          - Penumbra builds and its tests pass against the un-pinned library with the nonisolated(unsafe) holder removed
          - The full suite passes and a loaded soak run shows no new flake
      - title: WoodcaseScripting target and the read-only host
        ref: host-core
        labels: [scripting]
        blockedBy: [unpin, reports]
        desc: |
          Add the `WoodcaseScripting` library target (Package.swift; depends on Woodcase;
          `#if canImport(JavaScriptCore)` around every file, the WoodcaseViewer posture) and
          its test target. Build `ScriptHost`: one synchronous run that creates a JSContext,
          evaluates the prelude, installs `doc` and `console`, evaluates an ordered list of
          `ScriptSource` values — `.file(URL)` or `.text(String, name:)`, in one context — and
          returns a typed `ScriptRun`: one ordered timeline of events (write, log with level,
          warning), the completion value of the last source as JSON (null plus a warning event
          when it cannot cross), the document revision, the commit outcome, and an error carrying
          the source's name, line, column and quoted line. An optional sink closure receives each
          event as it happens. Library consumers pass strings they already hold; the CLI's
          repeated -F maps onto the list and holds no decision of its own. The host is written
          isolation-agnostic — no global-actor annotation anywhere — and its only runaway
          protection is a deadline that bridged calls check and throw on (`code: 'timeout'`);
          the process-ending watchdog is the CLI's, in the verb leaf. Each source is evaluated
          on its own with its own source URL, so an error reports that source's line, not a
          line in a concatenation. The report types are already public library types (reports
          leaf); the host returns them. This leaf ships the read side only: `doc.rev`,
          `doc.tree(address?, options)`, `doc.get`, `doc.lint`, `doc.schema`, over an
          `EditableDocument` the caller hands in. Tree rows come from `TreeView.rows(of:settled:…)`
          over one lazily built `SettledTree`, held by the host and dropped by any write (the
          write side lands in the next leaf; this leaf ships the cache and its invalidation hook).

          Bridging shape, spiked 2026-09-07: `@convention(block)` closures via
          `setObject(_:forKeyedSubscript:)`; throw into JS by assigning
          `JSValue(newErrorFromMessage:in:)` to `context.exception`; marshal node subtrees and
          reports through JSON (JS `JSON.stringify` on the way in, the library's Codable on the
          way out) rather than `toDictionary()`. Every error crossing into JS is a
          `WoodcaseError` with `code` (the EditingError case name), the remedy sentence from
          BatchErrorMessage+Editing.swift, and `candidates` where the error carries them.

          The prelude is a Swift string constant (ViewerScript.swift is the precedent). It makes
          `doc` a Proxy whose unknown-member access throws the teaching sentence listing the
          real members, and validates option-object keys per member, naming the keys that
          member takes. `console.log/warn/error` join arguments with spaces and render objects
          as JSON. There is no event loop: the prelude defines setTimeout, setInterval, fetch,
          require and a top-level `import` guard to throw a sentence saying scripts are
          synchronous and why, and a Promise as the completion value yields the null-plus-warning
          result. The public JavaScriptCore headers have no time-limit API (checked 2026-09-07);
          document that in the host's DocC.
        criteria:
          - The target builds under Swift 6 strict concurrency with no warnings, JavaScriptCore never appears in the Woodcase target, and no global-actor annotation appears in the host
          - A run over a file source and a text source in order shares one context, and an error in either is reported with that source's name
          - A run from a non-main actor works, and the sink receives events in the order the timeline records them
          - A script whose completion value is a function, a Promise or a cycle yields a null result and a warning event, never an unreadable string
          - setTimeout, fetch and require each throw the synchronous-scripts sentence, and an error in the second of two sources reports that source's name and line
          - doc.tree, doc.get, doc.lint and doc.schema return the same values the corresponding verbs print with --json, proven by a parity test over the batch.pen fixture
          - An ambiguous or missing address thrown into the script carries code, the verb's own sentence and a candidates array the script can read
          - Accessing an unknown member of doc throws a sentence naming every real member, and an unknown option key names the keys that member takes
          - A script past its deadline receives a catchable timeout error on its next doc call, asserted on outcome and not on elapsed time
          - An uncaught error is reported with its line, column and quoted source line
      - title: The write API over BatchApplier
        ref: host-write
        labels: [scripting]
        blockedBy: [host-core]
        desc: |
          Add set, add, replace, cp, mv, rm, override, vars.set/rm and themes.set/rm to `doc`,
          each translating its arguments into the matching `BatchOperation` and running
          `BatchApplier.applyOne(_:to:recorder:log:file:)` with the transaction's
          ActivityRecorder — the host adds no editing semantics of its own. Options are the
          verb's flags camel-cased (`at`, `name`, `props`, `detach`, `unset`, `rev`); `rev`
          becomes the line's revision pin and a conflict throws `code: 'revisionConflict'`.
          The return value is the WriteReport (id, path, rev, created with ids, divergences,
          node). No @tag support: the return value carries the id. Every write drops the
          settled-tree cache so the next read settles. Values arrive typed, as JSONL values do:
          the argv coercion rules do not apply, `$name` strings stay strings, and marshaling
          goes through JSON text so an integer from JavaScript is stored as an integer. The
          recorder is optional, so a library caller runs a script over an in-memory document
          with no activity log.

          Prove the per-call atomicity invariant: a write that throws has changed nothing
          (materialize before and after are equal; documentRevision unchanged), so a script
          that catches and continues works from a consistent document. Measure the
          write-then-read cost on local/ design-system file (1,850 nodes): a script that
          alternates 100 sets and 100 tree reads; record the figure and the command in
          WoodcasePerformance.md, and if it is over budget note the incremental-settle
          optimization in the doc rather than building it here.
        criteria:
          - Every member of doc that writes routes through BatchApplier.applyOne and appears in the activity log as the same event the verb would record, proven by a parity test against the verb
          - A write that throws leaves the document and its revision unchanged, and a script that catches the error continues and commits the rest
          - A read after a write returns settled rects that reflect the write
          - The write-then-read figure on the 1,850-node file is recorded in WoodcasePerformance.md with the command that reproduces it
          - An uncaught error after several successful writes commits nothing, and the activity log gains no events
          - An integer written from a script is stored as an integer and the node's revision equals the one the verb produces for the same edit
          - A run over an in-memory document with no recorder and no log succeeds and returns the same reports
      - title: The js verb
        ref: js-verb
        labels: [scripting]
        blockedBy: [host-write]
        desc: |
          `woodcase js <file> -F <script> [-F <more>…] [--as] [--guard…] [--dry-run] [--json] [--timeout]`
          in WoodcaseCommandCore, sitting exactly where ApplyCommand sits: one
          `PenFileTransaction.run(at:identity:log:effect:)`, entry guards via
          `BatchApplier.checkGuards`, then the host. stdout: one row per write as it happens
          (verb, path, id, (+N) created, divergences indented under the row), console.log
          lines interleaved, `result  <value>` and `document  <rev>` last. stderr: warnings
          and refusals only. `--json` is one object built from the same typed ScriptRun.
          Exit codes: uncaught script error 1 (file untouched), parse error 2 with line and
          message, stale guard or timeout 3, unreadable file 4. Register the verb in
          WoodcaseCLI.md's table with its exit codes, and read project/agents/cli-design.md
          before writing a single message. Tests spawn the binary through CommandFixture.

          `-F` repeats: the files are concatenated in order and evaluated in one context, so
          `-F helpers.js -F run.js` is the durable-code pattern the doc describes; an error's
          reported location names which file. Nothing persists between runs and nothing is
          auto-loaded — the plan doc's "No session" section says why; put that sentence in
          the verb's help.

          The verb is the host's sink: write rows and console.log lines go to stdout as they
          happen, console.warn/error to stderr, all of them in order under --json. The verb
          installs the process-ending watchdog on top of the host's deadline: a thread that at
          --timeout plus grace prints "script ran past N s; nothing was written" on stderr and
          exits 3 — safe because the transaction writes nothing before the body returns and the
          flock is the kernel's to release. This watchdog lives only in the verb.
        criteria:
          - The transcript in the plan doc runs as written against a fixture and prints the rows, result and document lines shown
          - A function defined in a first -F file is callable from a second, and an error in the second is reported with that file's name and line
          - A script that loops without calling doc exits 3 with the stderr sentence and leaves the file untouched, asserted on outcome and not on elapsed time
          - console.log lines appear on stdout between the write rows they were printed between, and console.error lines on stderr
          - Each exit code in the verb's row of WoodcaseCLI.md has a test that produces it
          - The text and --json forms are built from one ScriptRun value and a test proves every field printed in text appears in the JSON
          - --dry-run runs the script, writes nothing, and reports lint findings on the would-be document
          - --guard with a stale document pin refuses before the script runs, naming the writer as apply does
      - title: The find verb
        ref: find
        labels: [scripting]
        blockedBy: [host-core]
        desc: |
          `woodcase find <file> [<address>] <predicate> [--expand] [--props…] [--absolute] [--json]`
          in WoodcaseCommandCore: a read verb over the host's read side. Open the file with
          `PenFileTransaction.read`, settle once, build the same rows `tree` prints (with
          `--props` columns under `r.props`), evaluate the predicate — a JavaScript arrow
          function receiving one row — against each, and print the truthy rows in tree's text
          format and its --json shape, so `find` output pipes into everything `tree` output
          does. The predicate is a positional argument or `-F` for a longer one; it sees no
          `doc` and cannot write. Exit 0 with matches, 1 for none, 2 when the predicate does
          not parse or throws — the sentence names the row it threw on and lists the
          property names a row carries, since `r.fontSize` for `r.props['kind.fontSize']` is
          the mistake to expect. Register the verb and its exit codes in WoodcaseCLI.md and
          un-park `find` in project/backlog.md with a pointer here. Tests through CommandFixture.
        criteria:
          - The find transcript in the plan doc runs as written against a fixture
          - find output on a matching set equals the corresponding tree rows byte for byte in both text and JSON
          - A predicate that references a property outside r.props gets a sentence listing the row's members, exit 2
          - No matches exits 1 with nothing on stdout, and a predicate cannot reach doc
      - title: help js and the executable primer
        ref: help-js
        labels: [scripting]
        blockedBy: [js-verb, find]
        desc: |
          A `js` HelpTopic whose body is a short primer followed by the `.d.ts` declaration of
          `doc`, `WriteResult`, `TreeRow`, `WoodcaseError` and the option types. The primer
          teaches the three rules (one transaction, atomic calls, reads see settled layout),
          the no-session rule, that scripts are synchronous (no timers, no fetch, no await),
          that top-level const is shared across -F files, the `-F helpers.js -F run.js`
          pattern, and shows a fan-out,
          a measurement, a caught conflict and the one-line read-only query from stdin, each
          snippet ending in the read that verifies it. It also teaches the two routes: when a
          verb is enough (`cp --each`, `apply`, `find`) and when control flow makes it `js`.
          Two tests keep it honest: a RecipesTests-style extraction runs every snippet against
          a fixture; a reflection test evaluates the prelude, lists the members the Proxy
          exposes and their option keys, and checks them against the `.d.ts` in both
          directions. Add `js` and `find` to the design primer within its 140-line budget,
          and a `help js` pointer to the sentences the host throws.
        criteria:
          - Every snippet in help js runs green under the extraction test
          - Every runtime member and option key appears in the .d.ts and every declared one exists at runtime
          - help design still fits its line budget and names find for a query and js for a loop-shaped task
          - The primer states that nothing persists between runs and shows the repeated -F pattern
      - title: Out-of-band write detection and undo by transaction
        ref: external
        labels: [scripting, activity-log]
        blockedBy: [layout]
        desc: |
          Extract the revision-lineage comparison from UndoStep.decide into a library type in
          Sources/Woodcase/Files/ that both undo and the transaction use. Add
          `ActivityEvent.Kind.external` (no inverse, unattributed identity, the revision the
          file was found at). In `PenFileTransaction.run(at:identity:log:…)`, after the parse
          and before the body, compare the parsed documentRevision with the newest logged
          event for the file; on mismatch append an external event as the batch's first event
          and surface a note the verb prints on stdout: `note  <file> was rewritten outside
          woodcase since rev <short> (<identity>, <time>); the log has no record of that change`.
          A file with no log history is not a mismatch. undo reaching an external event refuses
          with the sentence naming the time; remove the stepOverUndone heuristic if the external
          row makes it unnecessary and say so in UndoStep's doc comment. `activity` renders the
          row. Update WoodcaseActivityLog.md and the undo section of WoodcaseEditor.md.

          Move undo itself into the library with the lineage type: UndoStep and the replay
          (UndoCommand's body) become public library API in Sources/Woodcase/Files/, so a
          library caller with the log can reverse an edit; UndoCommand keeps only argv and
          formatting.

          Undo by transaction (ruled 2026-09-07): every event carries the transaction's batch id
          and nothing reads it, so a forty-write script run is forty undos. `undo` now reverses
          the most recent transaction as one step — every event sharing the newest batch id, in
          reverse order, under one new undo event — and `-n` counts transactions; `--event`
          keeps the per-event form. The stale and blocked-by-other checks apply to the
          transaction's last event. Update the undo section of WoodcaseEditor.md and the
          activity-log article; the existing undo tests change expectation and the leaf's note
          says why. Independent of the host; runs in parallel with unpin and host-core, but
          touches PenFileTransaction, which unpin also edits — take the transaction's isolation
          change from main before starting, or coordinate the seam with the unpin agent.
        criteria:
          - Undo's step and replay are public library API, and the CLI's undo output for a single-event transaction is unchanged
          - undo after a batch or a script run reverses every write of that transaction as one step, and -n 2 reverses two transactions
          - undo --event reverses one event, as before
          - Rewriting the fixture with python3 json.dump between two set calls makes the second print the note once, and a third set prints no note
          - The activity log gains one external event carrying the revision the file was found at, and activity renders it
          - undo refuses to step past an external event with a sentence naming its time
          - A file edited only by woodcase never produces the note, proven over the full CLI suite
      - title: Imports on every route
        ref: imports
        labels: [scripting]
        blockedBy: [host-write]
        desc: |
          The typed edits addImport/updateImport/removeImport exist in EditOperation, but there
          is no BatchOperation, no verb and so no script member: a CLI caller cannot add, change
          or remove a library import by any route. Add a `BatchOperation.importOp` shaped like
          `variable` (alias, path; remove), a `woodcase imports set/rm` verb pair beside `vars`,
          and `doc.imports.set(alias, path)` / `doc.imports.rm(alias)` on the host. Same
          transaction, same log event kind (`import` already exists in ActivityEvent.Kind), same
          three-line echo. Read the import-namespaces article (PenImportNamespaces.md) first: an
          alias in use by a ref refuses removal the way vars rm refuses a referenced variable.
        criteria:
          - An import can be added, changed and removed from the CLI, from a batch and from a script, each logged as an import event
          - Removing an alias a ref still uses is refused with a sentence naming the instances, in every route
      - title: Documentation and the README
        ref: docs
        labels: [scripting, docs]
        blockedBy: [help-js, external, imports]
        desc: |
          WoodcaseScripting.md in the DocC catalog: the contract from the plan doc, the `.d.ts`
          verbatim from help js, the transaction rules, errors that teach, the watchdog and the
          platform note. Link it from Woodcase.md's Essentials and a Scripting symbol group, add
          a section to WoodcaseEditor.md ("When the answer is a loop") that hands off to it, add
          the README bullet and a short Scripting example under the CLI section, and add the
          article to CLAUDE.md's documentation list. Every figure names the command that
          reproduces it.
        criteria:
          - swift package generate-documentation builds with no warnings for the new article and the host's symbols at 100 percent coverage
          - README, WoodcaseEditor.md and CLAUDE.md point at the article
      - title: Agent trial of the host
        ref: trial
        labels: [scripting, finding]
        blockedBy: [docs]
        desc: |
          Run a Sonnet-class agent in a worktree against a task of the Quill shape on a copy of
          a real file: build a list from a template, fan out twelve rows, measure for overflow
          after layout, fix what overflows, and lint clean. Its only teaching is `woodcase help
          design` and `woodcase help js`; every route is available (cp --each, apply, find, js)
          and it may use any tool it likes. Record which route it reached for at each step and
          why, every sentence the host threw and whether the sentence was enough, and whether
          the activity log accounts for every byte the file changed by (walk the file's
          revision lineage and check for external events). Findings land as
          project/2026-MM-DD-scripting-host-trial.md; each sentence that was not enough
          becomes an issue-tree entry.
        criteria:
          - The finding doc records, step by step, which route the agent used and whether anything left the tool, with transcript excerpts
          - Every out-of-band write during the trial appears as an external event in the log
          - Each host sentence the agent could not act on is filed as an issue with the sentence quoted
      - title: Decide what the batch surface keeps
        ref: retire
        labels: [scripting, decision]
        blockedBy: [trial]
        desc: |
          Decision, informed by the trial's finding: does any verb-side loop surface — apply
          and its JSONL wire form, cp --each — go unused with js and find available, and is the
          primer simpler without it? The default is to keep everything; a retirement needs the
          trial's evidence as its note. If a surface is retired: BatchApplier, BatchOperation,
          BatchReport and the guard machinery stay as the planner the host and verbs share;
          WoodcaseBatches.md is rewritten as the library-level article; the recipes that used
          the surface become scripts under the extraction test; a grep test in the style of
          VendorWordsTests proves no caller-facing text still names it. Record the ruling here
          and in project/backlog.md whichever way it goes.
        criteria:
          - The ruling is recorded as a note on this leaf citing the trial doc
          - If anything is retired, no caller-facing text names it and the recipes that used it run as scripts
          - The full suite and swiftformat lint pass
```
