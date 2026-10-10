# 2026-10-10 — The CLI, audited as an agent reads it

A read-only pass over every `woodcase` verb, judged as an agent that reads tokens rather
than screen columns. It came out of reshaping `tree`'s text form (job `tS6FmP`, root
`LY4OvG` "Agent-readable CLI output"). An Opus agent built `.build/debug/woodcase` at
`0267cdb` and ran each verb against copies of `banking.pen`, `instances.pen`,
`tree-overflow.pen` and `imports.pen` from the test fixtures. The rubric was
[cli-design.md](agents/cli-design.md); its scripts are `run1.sh`–`run8.sh` in that
session's scratchpad, not kept. Nothing below is decided yet, and the outputs quoted are
the agent's, not re-run by the integrator — re-run a finding before building on it. Each
is a candidate leaf under `LY4OvG`.

## Decided and built alongside the audit

`tree` now leads with the name, indented by depth, then type, rect, any `--props`
columns, and the id last; a header row names the columns on every listing; `*`, `+N`
and the clip warning ride on the name. `find` prints the same columns flush, with no
`+N`, because its matches are not a walk — the audit's catch: indenting filtered rows
implies a nesting the listing does not show.

## Findings, most impactful first

**F1. The primer's revision advice produces a false conflict.** The primer and
`tree --help` say to quote the tree header's revision with `--rev`, but `--rev` on
`set` compares against the *node's* rev:

```text
$ woodcase tree instances.pen          → rev 3b26b4a88616583e  12 rows
$ woodcase set instances.pen Brd01 common.opacity=0.5 --rev 3b26b4a88616583e
Board (Brd01) has changed: rev was 3b26b4a88616583e, the node is now 7e235b5452789248 … [exit 3]
```

Bare `--guard <docrev>` fails the same way; only `--guard document=<rev>` works. Fix:
accept the document rev, or name the mistake in the error; correct the primer.

**F2. Plausible wrong answers at exit 0 or 1.**
- `find … 'r => r.rect.w > 10'` answers "no matches" (exit 1): the unknown-member guard
  covers top-level row keys only, not `rect`, `absRect` or `props`.
- `override … qa1/label contnet=Top` is stored at exit 0; `set` refuses the same typo.
- `tree … --props kind.contnet` prints a column of `-` and exits 0.
- `tree banking.pen ydTfa --props kind.content` prints `\\$24,562.80` for a stored
  `$24,562.80`; copying the cell back writes the wrong string.
- `vars set … --theme mode=drk` silently creates a new axis option `drk`.
- `imports set imports.pen V ./nope.pen` repoints two refs to a missing file at exit 0.

**F3. "No match" never suggests near misses.** `banking-home/headr` and `qa1/labl` get
"matches no node — run `woodcase tree …`", because the suggestion needs an exact final
segment. Property paths too: `content=` and `kind.contnet` list 36 paths instead of
leading with "did you mean `kind.content`".

**F4. Unknown subcommands mislead.** `vars remove banking.pen ink` reports "2 unexpected
arguments" with the usage of `vars list`, because the default subcommand swallows
`remove` (the verb is `rm`); `imports remove` too. `woodcase tre x.pen` gets no
suggestion.

**F5. Cells with spaces break row parsing** in tree, find, lint, vars, activity and undo:
names (`banking-home / Dark`), `--props` values (`Good morning`), vars' middle column
(`1 ref, 1 var`). With the id last, splitting from the right works only while no other
cell has spaces. Proposed rule: a cell containing whitespace is JSON-quoted; `-` means
absent, and a literal `-` is quoted.

**F6. Revision labels and JSON keys disagree.** Text: `rev X  N rows` (tree, find);
`rev  X` + `document  X` (set, add, cp, mv, override); `revision X` (vars, imports,
undo); `— revision X` (apply); none at all (lint, vars text, imports text, themes).
JSON: `revision` is the document rev in tree, vars, imports and undo but the node rev in
get; set, add, apply and js use `documentRevision` / `nodeRevision`.

**F7. Row shapes differ across list verbs.** lint `severity check path (id) message`;
activity `HH:MM:SS | who | op | path` (pipes, no date, an empty identity cell); undo
`op who ISO path`; get's header `id path rev` against the write acks' `path id`;
generate `warning: id: message`; shot `id key=value…`.

**F8. Some writes do not say what they made.** `render` and `generate` print
`Rendered 1 file(s) to <dir>` with no file list and no `--json`; `bundle` does not say
the original `.pen` was removed. The output flag is `--out` (shot), `--output-dir`
(render) and `--output` (generate).

**F9. Token cost.** The missing-font warning (~330 characters) lands on every read and
write; remedies echo expanded absolute paths rather than the path typed;
`override-target-not-found` lists every descendant (tens of KB from one
`rm --detach --dry-run`); `duplicate-name` repeats a ~400-character explanation per
finding; the `vars set` ack prints every value twice; `apply --json` and
`activity --json` carry Swift's `"_0"` enum encoding and full inverses.

**F10. Smaller.** `add -F bad.json` leaks `DecodingError.dataCorrupted`; `add` makes a
same-named sibling silently; cp's root placement is a `divergence` where it is a note;
empty reads disagree (prose naming `document.pen` vs nothing); `bundle` under the
sandbox claims "the edit is on disk" when nothing was written; `generate`'s permission
error has no path or remedy; `themes`, `render`, `generate` and `migrate` have no
`--json`.

## Gaps in cli-design.md

Cell encoding (F5) and the tree decision (a header row, the address last, no meaning in
padding); one revision token accepted everywhere or labeled by scope, and one JSON key
per meaning (F1, F6); near misses by edit distance on the misspelled segment, for
property keys, subcommands and enum values too (F3, F4); short, deduplicated stderr
warnings that echo paths as typed (F9); the exit code for "refused pending a flag"
(2 today); capped lists in errors and lint ("+N more"); file outputs under "a write
answers with what it made" (F8).
