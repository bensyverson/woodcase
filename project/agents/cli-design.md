<!-- agents:begin cli-design@ade2be -->
# CLI design for agents

An agent composes tools the way a shell does: run a verb, read the output, branch on the exit code. The measure of a CLI built for agents is how little the agent must hold in its head to use it correctly, and how hard it is to misuse. These rules are distilled from `job`, `sleepy` and `woodcase`; when building a new CLI, or a new verb on one of those, they are the defaults.

## Grammar

- **One shape per verb class.** `tool <verb> <target> [args] [--flags]`, the same order everywhere; a flag that means one thing on one verb means the same on all. Read verbs, act verbs and management verbs are distinct classes with distinct preconditions — say which class a verb is in its help.
- **A bare invocation is a primer, not an error.** `tool` alone prints what the tool is for, the verbs grouped by role, and the one command to run first. `tool <verb> --help` carries one worked example.
- **Help never has preconditions.** Docs, `--help`, `schema`, `recipes` and `doctor` work with no file open, no session, no network. A tool that won't explain itself until it is set up teaches nothing.
- **Bodies come from files, never inline.** Free text goes in with `-F <file>` (`-F -` for stdin); `-m "…"` is a footgun because the shell sees it first. Structured input is a file of the format the tool already speaks — a `.pen` subtree, a YAML plan — not a bespoke DSL.
- **Address things by name where a name exists, by id everywhere.** Names resolve to ids at write time and are stored as ids. Ambiguity is an error listing every candidate with its full path; no match is an error naming near misses — **never a silent no-op**. Things the tool creates must be named; things it did not create may be unnamed and are flagged as such on read.
- **Identity is `--as <name>`**, defaulting from an environment variable or a recorded default, never from the OS account. No registration step: naming an identity is creating it. Every write is attributed.

## Output

- **stdout is the API.** The default output is the tersest faithful form — an indented outline, one row per item, JSON only where the data is inherently structured — and a stable machine shape is always one `--json` away. Same bytes in a pipe and in a terminal; no color or spinner leaks into a parse.
- **A write answers with what it made.** Every mutating verb prints the name → id map of what it created, as a tree that mirrors the structure, so the next command needs no lookup. A read answers with addresses that write: an expanded view hands back the paths a later mutation accepts.
- **A read after a write sees settled state, in the same invocation.** Layout, indexes, derived values — whatever the tool computes — is computed before it is reported. Reporting a pre-settlement value is a plausible wrong answer, and those are worse than errors.
- **Reads carry a revision.** Anything an agent might reason about and then mutate returns a token (a content hash, a version); mutations accept it and fail loudly if the world changed underneath. Scope the token as narrowly as the data allows — per node, not per file — so unrelated work never conflicts.
- **Rows over documents.** For anything list-shaped, one compact line per item with the columns the agent branches on — id, type, name, size, a problem flag — beats a JSON object per item by an order of magnitude in tokens. Depth limits and `--props` widen on request.

## Exit codes

One table, shared by every tool in the house; an agent learns it once.

| Code | Meaning |
|---|---|
| 0 | Success, or the asserted condition holds |
| 1 | Clean negative: the check ran and the answer is no |
| 2 | Usage error: the invocation itself was malformed |
| 3 | Conflict or timeout: the world changed, a lock or budget ran out — last state attached |
| 4 | Target failure: the file, page or record could not be loaded |
| 5 | Environment error: missing session, dead helper, wrong setup |

- **Assertion verbs are scripts' friends**: `--exists`, `--min`, `lint` return 1 on a finding so `&&` and `||` do the branching.
- **Everything terminates.** Every operation that can wait has a default budget; "no answer" becomes exit 3 with a reason, never a hang.

## Errors that teach

- **An error names the thing by its path, says what happened, and says the next command.** "task is claimed by jars", "`Card/Title` is ambiguous: `Card/Header/Title` (`kXFgb`), `Card/Footer/Title` (`Z3BoD`)", "4 instances would be detached; pass `--detach`". Test this: every error type maps to a message with a remedy.
- **Consequential destruction is refused, then explained.** When an operation's effect exceeds its target — deleting a component with live instances, removing a variable that nodes reference, dropping a claimed task — refuse without an explicit flag and list what would be affected.
- **Success messages teach too.** The ack on a claim, an insert or a close carries the one thing the agent should do next and any warning it must read ("closing the last child will close the parent").
- **Never a plausible wrong answer.** A blank image at exit 0, a diagnostic computed from stale state, `undefined` for something that exists — if the true answer is unavailable, say so and exit non-zero.

## State

- **Ephemeral by default, state by name.** A bare invocation leaves no trace. Persistent things — sessions, jars, claims — exist only when named; naming one is creating it, and anything named is listable and prunable.
- **Stateless commands over a stateful file beat a daemon.** Open → apply → write atomically under a lock; the file is the truth and any other tool may read it. A daemon earns its keep only for live merging of unsaved state, sub-second presence, remote peers, or a warm cache that measurably matters — write the trigger down before building one.
- **An append-only log of attributed events** is the cheapest durable state: it is the history, the dashboard, the undo source and the feed other tools consume. JSONL in a well-known, discoverable place (`~/.tool/`), rotated by size.
- **Undo is a verb**, replaying the log's inverses for one identity, and it refuses when the revision no longer matches rather than guessing.

## Batches

- **Apply what can be applied.** A batch is one op per line; a failed op is skipped, ops that depend on it are skipped as *cascaded*, independent ops proceed, the result is one status line per op. `--atomic` opts into all-or-nothing. Full rollback by default punishes a typo in op 11 with the loss of ops 1–10.
- **Forward references by tag.** An op may label what it creates (`@hero`) so later lines in the same batch can address it before an id exists.
- **Retry is a patch, not a resend.** Given the previous report, re-run only the failed and cascaded lines against the current state.

## Discoverability

- **Progressive: the primer, then the verb's help, then `recipes`** (goal → verb routing, "prove the page makes no external requests → `wire`"), then `schema` for any grammar the tool imports. The aim is that no external skill file or agent-facing manual is needed; if one is, the help is incomplete.
- **Every read has a cheaper sibling.** Offer the structural view (tree, outline, accessibility) before the pixel view; a screenshot is the last resort, sized on request (`--max`), scoped to the smallest node, and annotated (`--grid`, `--outline`) so the pixels can be mapped back.
- **Deterministic by construction.** Fixed sizes, a named theme, no ambient state: the same invocation produces the same bytes, and a golden test pins it — measurements (timings, timestamps) are the only documented exception.

## Building one

- **Library + thin executable**: the verb is an adapter over a core the app or tests call directly; an adapter that holds a decision is a bug.
- **Kick the tires before designing the verbs.** Use the nearest existing tool for a real task as an agent would, write a dated DX note pairing each finding with the rule it implies, and let those rules become the plan's acceptance criteria.
- **Tests drive the binary** against fixture copies in a temp directory, asserting output bytes and exit codes; every error path has a test that reads the remedy.
<!-- agents:end cli-design -->
