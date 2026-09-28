# The JavaScript Host

Run a program over a .pen file, inside one transaction: read, decide and write in one
pass.

## Overview

Agents write code. Given twelve list rows that differ by one string, or a question like
"every text node under 12 pt", a model reaches for a loop before it reaches for a verb.
That instinct is not the problem — a rule against it would only be a rule a tool fights
its user with. The harmful case is narrower and specific: *the agent wrote code that
opened the .pen file with a JSON parser*, skipping the file lock, the activity log,
`undo`, id minting and the divergence sentences. That happens because writing code is
natural and there is nowhere for that code to go.

So the host gives it somewhere to go. `woodcase js` runs a JavaScript program inside one
file transaction, with a `doc` object whose members are the editing verbs one for one.

```javascript
// woodcase js batch.pen -F fan-out.js --as ana
const rows = [
  { name: 'Chip Alpha', label: 'alpha' },
  { name: 'Chip Beta', label: 'beta' }
];
for (const row of rows) {
  doc.cp('Component', 'Board', {
    props: { 'common.name': row.name, 'Label/kind.content': row.label }
  });
}
doc.tree('Board').filter(r => r.depth === 1).map(r => r.address)
```

```text
$ woodcase js batch.pen -F fan-out.js --as ana
cp           Board/Chip Alpha  3uKNL
cp           Board/Chip Beta  iPAIz
result  ["Board/Chip","Board/Chip Alpha","Board/Chip Beta"]
document  3db8fa5305c3a62b
```

Every transcript here is real output from `Tests/WoodcaseTests/Fixtures/batch.pen` and
`banking.pen`, run in a scratch directory with its own log. Ids and revisions are minted
per insert, so a run of your own prints different ones.

The engine is JavaScriptCore: a system framework everywhere this package ships an app,
with no filesystem and no network of its own, running the language a model is most
fluent in.

The host is the `WoodcaseScripting` target — a library, so the editor and the CLI run the
same programs the same way. `woodcase help js` prints this contract in the terminal, and
the declaration below is the same text that topic ships. <doc:WoodcaseEditor> is the
loop this fits into and <doc:WoodcaseCLI> the verb table it sits in.

## Which route

A verb is often enough, and reaching for a program when a verb would do is its own cost.

| Route | The question it answers |
| ----- | ----------------------- |
| A single verb | One edit, addressed by name |
| `cp --each rows.jsonl` | One template, fanned out over data |
| `apply` (<doc:WoodcaseBatches>) | A fixed list of edits, in one transaction |
| `find` | A question over the rows `tree` prints |
| `js` | Control flow: what to write depends on what a read just said |

Reach for `js` when the loop carries a running total, when the second write depends on
the first, or when a measurement decides whether to commit at all. That last one is what
no batch can express.

The exit codes differ because the questions do. A `find` predicate that throws exits 2 —
the predicate *is* the invocation, and a question that cannot be asked is malformed. A
`js` script that throws exits 1 — the script is the check, it ran, and the answer is no.
Either way the file is untouched.

## The three rules

**One transaction.** Nothing is written until the script ends without an uncaught error.
A throw, a refusal you did not catch, the `--timeout`, a kill: the file is byte for byte
what it was and the activity log gained nothing. There is no partial commit to reason
about, and `undo` reverses the whole run as one step.

**Each call is atomic.** A call validates before it mutates, so a call that threw has
changed nothing. Catch it and carry on: the document is consistent, and everything the
run does afterwards still commits.

**Reads see settled layout.** Every read after a write lays out again first whatever the
write could have moved — the roots it touched, the roots drawing a component it touched,
or every root after a variable, theme or import change — so a rect from `doc.tree`
includes what you just wrote. Measure after the write, and
throw rather than commit when the measurement is wrong.

The third rule is what makes the first one worth having:

```javascript
// woodcase js banking.pen -F measure.js --as ana
doc.override('banking-home/transactions-section/t1/info/merchant', {
  content: 'Coffee at the corner shop'
});
const tall = doc.tree('banking-home/transactions-section')
  .filter(r => r.depth === 1 && r.rect.height > 64);
if (tall.length) {
  throw new Error(`${tall.length} rows overflow: ${tall.map(r => r.address).join(', ')}`);
}
doc.tree('banking-home/transactions-section')
  .filter(r => r.depth === 1).map(r => r.rect.height)
```

```text
$ woodcase js banking.pen -F measure.js --as ana
override     banking-home/transactions-section/t1  aqCub
result  [30,59,59,59,59]
document  62ba351b0d8a2cba
```

Lower that 64 to 40 and the same script refuses to commit what it just wrote. The write
row still prints — it happened, on the document — and then the promise the transaction
keeps:

```text
$ woodcase js banking.pen -F overflow.js --as ana
override     banking-home/transactions-section/t1  aqCub
overflow.js:8:18  4 rows overflow: banking-home/transactions-section/t1, …
    throw new Error(`${tall.length} rows overflow: ${tall.map(r => r.address).join(', ')}`);
nothing was written; banking.pen is byte for byte what it was.
[exit 1]
```

## No session

Nothing persists between runs and nothing is auto-loaded. A run is a process holding a
file lock; when it ends, its globals end with it.

Durable code is a file. `-F` repeats, and `woodcase js design.pen -F helpers.js -F run.js`
evaluates the helpers first, in the same context, so a function defined in the first is
callable from the second — and an error in the second reports *that* file's line rather
than a line in a concatenation. Top-level `const` and `let` are shared across the sources,
so declaring the same name in both is a syntax error: exit 2, naming the file and the
line.

## Synchronous, and alone

A script runs to completion in one pass. There is no event loop, so `setTimeout`,
`setInterval`, `fetch`, `require` and top-level `await` each refuse with a sentence
saying why, and a Promise as the last expression is a value nothing will ever resolve.

The script sees `doc`, `console` and the language, and nothing else: no files, no
network, no modules. What it needs comes in from the shell that runs it — which is also
what makes a one-line question worth writing:

```text
$ echo 'doc.lint().length' | woodcase js batch.pen -F -
result  3
document  4370d9cd421d3a17
```

## What comes back

Every write prints a row as it happens — the member of `doc` that made it, the path, the
id, `(+N)` for the descendants a creating verb made, and any divergences indented under
it — with `console.log` between the rows where the script printed it, and `console.warn`
and `console.error` on standard error.

The last expression of the last source is the run's `result`, as JSON: end with
`({ rows: doc.tree('List'), lint: doc.lint() })` for a structured answer. There is no
wrapping function and no top-level `return`, so a one-liner from standard input works
unchanged. A value that cannot cross `JSON.stringify` — a function, a Promise, a symbol,
a cycle — produces no `result` and a warning saying which it was, never a silent
`[object Object]`.

`woodcase js … --json` prints none of that live and one object at the end: `events`
(a write carries `member` and `write`; a root overlap carries the `lint` line as `text`),
`result`, `documentRevision`, `commit`, `error` and `warnings`, plus `dryRun` and `lint`
for a `--dry-run` rehearsal.

## When a call refuses

Every refusal is a `WoodcaseError`: the sentence the verb would have printed, a `code` to
branch on, and `candidates` when the sentence listed any. `doc.setProps` names doc's real
members; an unknown option key names the keys that member takes; `variableInUse` and
`importInUse` refuse to strand a reference, and `{ force: true }` opts into it;
`revisionConflict` is a stale `rev` on a node and `documentRevisionConflict` a stale one
on a root-level `add` or `cp`; `timeout` is the budget spent, and every later call
refuses the same way.

A caught one is an ordinary branch, because the call that threw changed nothing:

```javascript
// woodcase js batch.pen -F retry.js --as ana
const pinned = '9c1b04e6f2a71d38';
try {
  doc.set('Canvas/Title', { 'kind.content': 'Hello' }, { rev: pinned });
} catch (error) {
  if (error.code !== 'revisionConflict') throw error;
  console.warn(`Canvas/Title moved since ${pinned} — re-reading and retrying`);
  doc.set('Canvas/Title', { 'kind.content': 'Hello' },
    { rev: doc.get('Canvas/Title').revision });
}
doc.get('Canvas/Title').node.content
```

Most codes are the editing layer's own case name, unchanged — `addressNotFound`,
`ambiguousAddress`, `revisionConflict`, `documentRevisionConflict`, `unknownProperty` and
the rest — so a script branches on the same word a `--json` report carries. The ones that
belong to the host itself are `timeout`, `syntaxError`, `unknownMember`, `unknownOption`,
`badArgument`, `synchronousOnly`, `unknownNodeType`, `sourceUnreadable`, `variableInUse`,
`importInUse` and `scriptError`; they are the `ScriptErrorCode` constants in
`WoodcaseScripting`.

## The `doc` object

Property paths are the prefixed vocabulary `set` takes — `common.name`, `kind.content`,
`null` to clear one — except on `override`, which takes the raw .pen names an instance's
`descendants` map holds; <doc:WoodcaseBatches> has the asymmetry and why it is in the
storage rather than in what a line may write. An address is an id, a name path, or a path
stepping into an instance; a parent may be `null`, meaning the document root. Values
arrive typed: an integer written here is stored as an integer, and a `$name` string stays
a string.

This is the declaration `woodcase help js` prints, and a test holds the two to each other
and both to the running prelude — a declaration that has drifted from the runtime is
worse than none, because it teaches a call that throws.

```typescript
declare const doc: {
  /** The document's revision, live: it changes after every write. */
  readonly rev: string;

  /** One row per node under `address`, or the whole file — `tree --json`. */
  tree(address?: string | null, options?: TreeOptions): TreeRow[];
  /** One node as the file stores it, with its revision — `get --json`. */
  get(address: string, options?: GetOptions): NodeReport;
  /** What is wrong with the document as it stands now — `lint --json`. */
  lint(address?: string | null, options?: LintOptions): LintFinding[];
  /** Every property a node type takes, or the overview — `schema --json`. */
  schema(type?: string | null): Schema;

  set(address: string, props: Props, options?: RevOptions): WriteReport;
  add(parent: string | null, node: PenNode, options?: PlaceOptions): WriteReport;
  replace(address: string, node: PenNode, options?: RevOptions): WriteReport;
  cp(source: string, parent: string | null, options?: CpOptions): WriteReport;
  mv(address: string, parent: string | null, options?: PlaceOptions): WriteReport;
  rm(address: string, options?: RmOptions): WriteReport;
  override(address: string, props: RawProps, options?: OverrideOptions): WriteReport;

  vars: {
    set(name: string, variable: PenVariable): WriteReport;
    rm(name: string, options?: ForceOptions): WriteReport;
  };
  themes: {
    set(axis: string, options: string[]): WriteReport;
    rm(axis: string): WriteReport;
  };
  imports: {
    set(alias: string, path: string): WriteReport;
    rm(alias: string, options?: ForceOptions): WriteReport;
  };
};

interface TreeOptions { depth?: number; expand?: boolean; props?: string[]; theme?: Theme }
interface GetOptions { expand?: boolean }
interface LintOptions { exclude?: string[]; severity?: string; theme?: Theme }
interface RevOptions { rev?: string }
interface PlaceOptions { at?: number; rev?: string }
interface CpOptions { at?: number; props?: Props; each?: Props[]; rev?: string }
interface RmOptions { detach?: boolean; rev?: string }
interface OverrideOptions { unset?: string[]; rev?: string }
interface ForceOptions { force?: boolean }

type Props = { [path: string]: any };     // common.name, kind.content, Child/kind.fill
type RawProps = { [name: string]: any };  // content, not kind.content — override only
type Theme = { [axis: string]: string };  // { mode: 'dark' }

/** A settled tree row — what `tree --json` and `find --json` print. */
interface TreeRow {
  id: string; address: string; rev: string; depth: number;
  type: string; name: string | null;
  rect: Rect | null; absRect: Rect | null;   // the parent's space, and the document's
  clip: 'none' | 'partial' | 'full';
  overflowAxes: ('horizontal' | 'vertical')[];
  isReusable: boolean; isInstance: boolean; isSlot: boolean; childCount: number;
  properties?: Props;     // only the paths the `props` option asked for
  props?: Props;          // the same bag under find's spelling — one guarded view
}
interface Rect { x: number; y: number; width: number; height: number }

/** What every write answers with, `vars`, `themes` and `imports` included. */
interface WriteReport {
  id?: string;              // absent for a variable, a theme axis, an alias
  path?: string;            // the name path, or the name that was written
  nodeRevision?: string;    // absent when the node no longer exists
  documentRevision?: string;
  created?: CreatedNode[];  // add, replace and cp: the subtree that came to be
  divergences?: Divergence[];
  node?: PenNode;           // the stored node, children stripped
}
interface CreatedNode { id: string; name?: string; children: CreatedNode[] }
interface Divergence { kind: string; severity: 'divergence' | 'note'; target: string;
  requested: string; applied: string; note: string }
interface NodeReport { revision: string; node: PenNode; props?: object[] }
interface LintFinding { check: string; severity: string; message: string;
  nodeID?: string; path?: string }
interface Schema { type?: string; summary?: string; properties?: object; [key: string]: any }
type PenNode = { type: string; name?: string; children?: PenNode[]; [key: string]: any };
type PenVariable = { type: 'boolean' | 'color' | 'number' | 'string'; value: any };

/** Thrown by every member. `instanceof WoodcaseError` holds for all of them. */
declare class WoodcaseError extends Error {
  code: string;
  candidates: { id: string; path: string }[];
}
```

## Calling the host from Swift

The types below live in the `WoodcaseScripting` target rather than in `Woodcase`, so they
carry no symbol links here; `swift package generate-documentation --target
WoodcaseScripting` builds their own reference.

`ScriptHost.run(_:over:timeout:remedy:diagnostics:recorder:sink:)` is the whole API. It
takes the sources, an open ``EditableDocument``, and a budget, and it never throws:
everything that can go wrong is part of the answer.

```swift
let run = ScriptHost.run(
    [.file(helpers), .text("doc.lint().length", name: "<argv>")],
    over: document,
    timeout: .seconds(30),
    recorder: recorder
) { event in print(event) }
```

- **`ScriptSource`** is `.file(URL)` or `.text(_, name:)`. The list is evaluated in order
  *in one context*, each with its own source URL, which is what lets a helpers file
  precede the run that uses it and still have an error report the right file's line. Where
  a script comes from is the caller's decision and never the host's: the CLI's repeated
  `-F` maps onto this list, and a library consumer hands over strings it already holds.
- **`ScriptRun`** is one timeline rather than several arrays, because *what was printed
  before which write* is part of the answer. `events` is `.write(member:_:)` carrying a
  ``WriteReport``, `.log(level:text:)`, `.warning(_:)` and `.overlap(_:)` — a root
  overlap the run created, as the ``LintFinding`` `lint` reports — in the order they
  happened;
  `result` is the last source's completion value as ``AnyCodable``; `documentRevision` is
  where the document ended; `commit` is `wrote`, `unchanged`, `previewed` or
  `rolledBack`.
- **`sink`** is called synchronously with each event as it happens, for a live
  transcript. The same events come back in `events`, so a caller that only wants the
  answer can ignore it.
- **`ScriptError`** carries the sentence, the `code`, the source, line and column, the
  quoted source line, and the candidates a refusal named — as values, not as prose inside
  the message. `ScriptErrorCode` holds the host's own codes as constants rather than an
  enum, so a script's `err.code` and a Swift `switch` share one spelling of each word.
- **`ScriptHost.members()`** evaluates the prelude in a context of its own and asks it what
  `doc` exposes: one `ScriptMember` per member, with its kind and its option keys, in
  declaration order. It reads no document and runs no script. This is what keeps the
  declaration above honest, and it is the list an unknown-member sentence names.

Two things the host deliberately does not do. It adds no editing semantics: every write
is one batch operation through ``BatchApplier``, so the divergence detection, the revision
guard and the activity log are the verbs' own. And it never writes a file — whether a run
is committed belongs to whoever opened the document. The `js` verb wraps the run in one
``PenFileTransaction``, which is where "nothing was written" comes from; pass that
transaction's ``ActivityRecorder`` and every write the script makes is logged exactly as
the matching verb logs it, or pass `nil` and a run over an in-memory document logs
nothing and reports the same.

No global actor appears anywhere in the target, and none is needed: `JSContext` is not
`Sendable` and neither is ``EditableDocument``, but the whole run lives inside one
synchronous function, so nothing it holds crosses an isolation boundary and the compiler
can prove it. Call it from the main actor, from an actor of your own, or from nowhere in
particular.

## The watchdog

The host's own budget is a *deadline* every bridged call checks: past it, the next `doc.*`
call throws `timeout`, which a script may catch to clean up. That bounds every script that
does work.

It does not bound `while (true) {}`, which calls nothing. The public JavaScriptCore
headers on macOS 15 carry no execution-time limit and no interrupt to ask for — checked
2026-09-07, `grep -ri 'TimeLimit\|Interrupt'` over the framework's `Headers` finds only
licence text — so the CLI adds the last resort. `ScriptWatchdog` is a thread (not a
`Task`: a spinning `JSContext` never yields, so a cooperative-pool task beside it may
never run) that outlives the deadline by a two-second grace, says what happened, and ends
the process with exit 3:

```text
$ echo 'while (true) {}' > spin.js
$ woodcase js batch.pen -F spin.js --timeout 1
script ran past 1 s; nothing was written
[exit 3]
```

Killing the process loses nothing, which is the point of the sentence: ``PenFileTransaction``
writes no bytes until its body returns, and the advisory `flock` is the kernel's to
release. The watchdog is the CLI's and never the library's — a host that called `exit`
inside an editor would take the editor with it, so a library consumer that needs a hard
bound on a pure loop runs the host out of process. `--timeout` defaults to 30 seconds.

## What `find` shares with it

`find` runs a JavaScript predicate over the rows `tree` prints, through the same host's
read side; the CLI holds no JavaScript of its own. It is a read verb: a shared lock, no
writes, and no `doc` at all.

The one thing worth knowing is why a row refuses a member it does not have. The mistake
the whole predicate prelude exists for is `r.fontSize` written for
`r.props['kind.fontSize']`. On a plain object that reads `undefined`, and `undefined < 12`
is `false` — so the run succeeds, prints nothing, exits 1, and the answer looks like "no
rows match" rather than "you asked the wrong question". A silent wrong answer is the worst
outcome a query tool has, so every row is a `Proxy` that refuses an unknown member and
lists the ones it has:

```text
$ woodcase find banking.pen 'r => r.fontSize < 12'
The predicate threw on row #j4hLC (j4hLC): a row has no fontSize. Its members are
absRect, address, childCount, clip, depth, id, isInstance, isReusable, isSlot, name,
overflowAxes, properties, rect, rev, type, and a property of the node itself is read
as r.props['kind.fontSize'] with --props kind.fontSize on the command line.
[exit 2]
```

The same guard sits on `r.props`, which refuses a property path `--props` did not ask for,
and on `doc`, which is defined only to explain that it lives in `js` instead. The rows
`doc.tree` hands a script are the same guarded rows, refusing the same mistakes in the
script's own dialect: `props: ['kind.fontSize']` where `find` says `--props kind.fontSize`. The refusals
are branded internally so a sentence the prelude wrote is never reported at the line the
caller typed — a JavaScriptCore `Error` records the line it was *constructed* on.

**A predicate that is not a function names the shape it needs, not the symptom.** A
predicate is an arrow function of one row, and the everyday mistake is typing the row's
own body instead — `r.type === "text"` for `r => r.type === "text"`. Evaluating a
function literal never runs its body, so evaluating that text on its own throws
JavaScriptCore's own `ReferenceError`, "Can't find variable: r" — accurate about what
broke, and silent about what to do next. The host recognises the shape rather than
repeating the raw error: any `ReferenceError` thrown by evaluating the whole predicate
text, on its own, can only mean the text is not a function literal at all, whatever
identifier it names.

```text
$ woodcase find banking.pen 'r.type === "text"'
The predicate: a predicate is a JavaScript arrow function of one row — `r => …` — not a
bare expression; r only exists inside that arrow function's parameter list
[exit 2]
```

## Which platforms

JavaScriptCore is a system framework on macOS and iOS and absent on Linux, and SwiftPM
cannot make a target conditional — only a dependency. So `WoodcaseScripting` is always
declared and every file inside it is wrapped in `#if canImport(JavaScriptCore)`; on a
platform without the framework it builds to nothing, and the package stays cross-platform.

The boundary is the point. ``Woodcase`` itself never sees JavaScriptCore, and that is not
a convention anyone has to remember: `ScriptingIsolationTests` reads every source file
under `Sources/Woodcase` and fails on the word, and reads every source under
`Sources/WoodcaseScripting` and fails on a `@MainActor` or `@globalActor`. Both are rules
a compiler will not notice being broken — a stray import builds perfectly well on a Mac
and takes the whole package off Linux.

## Topics

### The route in

- <doc:WoodcaseBatches>

### What a write goes through

- ``BatchApplier``
- ``BatchOperation``
- ``WriteReport``
- ``WriteDivergence``
- ``EditableDocument``
- ``EditingError``
- ``NodeAddressCandidate``

### What a run is wrapped in

- <doc:WoodcaseActivityLog>
- ``PenFileTransaction``
- ``ActivityRecorder``
- ``RemedyDialect``
