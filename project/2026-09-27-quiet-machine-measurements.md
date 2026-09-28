# Quiet-machine measurements, 2026-09-27

Four measurement leaves taken together while no other agent was building: `xrqqge`
(layout and parse after the iterative rewrite), `U7wvkV` (the PenExtras capture),
`Tdgxuz` (the write-then-read pair) and `gh42Xb` (the `shot` binary row). Main was
`4564016`. The rows they change are in `WoodcasePerformance.md`; this note holds the A/B
detail behind them.

## Machine state

Apple silicon, 8 cores. No builds ran during any timing, but the machine was not idle:
macOS background work (`mediaanalysisd`, `spotlightknowledged.updater`,
`ANECompilerService`, `dasd`, `photolibraryd`) held one to two cores for most of the
session, and the 1-minute load average sat between 4 and 14 while a timing ran — every
timing started below 5 (`sysctl -n vm.loadavg`, checked before each run), but running
`swift test` itself pushes it up. Every comparison below is therefore **interleaved** — the
two builds alternate run by run, so both see the same background — and quotes the minimum
of 5 runs, each run itself the minimum of 5 in-process repetitions. The spread between a
run's repetitions was under 2 % throughout.

Each table gives the command it ran; an older commit was built in its own
`git worktree add --detach` checkout and the same command run there with
`--package-path`, alternating with main.

## xrqqge — layout and parse after the iterative rewrite

```sh
# In each worktree, interleaved, 5 rounds:
WOODCASE_TEST_PROFILE=1 swift test -c release --filter PerformanceBudgets 2>&1 \
  | grep -E 'BUDGET|PROFILE'
```

`936a89d` (before `c95e6c3`) against main, release, minimum of 5 runs, load 4.7–13.6:

| Budget | `936a89d` | main | change |
|---|---|---|---|
| `tree` `woodcase-app.pen` | 248.8 ms | 271.7 ms | **+9.2 %** |
| `tree` synthetic 5000 | 344.3 ms | 370.0 ms | +7.5 % |
| `set` `woodcase-app.pen` | 108.6 ms | 110.5 ms | +1.7 % |
| `set` synthetic 5000 | 887.0 ms | 899.6 ms | +1.4 % |
| `shot` `woodcase-app.pen` | 231.1 ms | 246.7 ms | +6.8 % |
| `shot` synthetic 5000 | 291.0 ms | 317.8 ms | +9.2 % |

The profile (one pass after the timed repetitions, minimum over the 5 runs) puts it in
layout, and a little in parse:

| Stage | `woodcase-app.pen` before → main | synthetic before → main |
|---|---|---|
| parse | 88.5 → 88.9 ms | 208.1 → 218.8 ms |
| expand | 96.9 → 100.9 ms | 1.9 → 2.0 ms |
| resolve | 1.3 → 1.7 ms | 4.5 → 6.1 ms |
| layout | **21.6 → 33.4 ms** | **48.0 → 60.1 ms** |

Bisecting the same way (`TreeTests` only, 5 interleaved rounds each) splits it between two
commits, neither over 10 % on its own:

| Pair | `tree` app | `tree` synthetic | layout app | layout synthetic | parse synthetic |
|---|---|---|---|---|---|
| `dd7866c` → `c95e6c3` (iterative walk), load 4.3–4.8 | 245.2 → 255.7 (+4.3 %) | 338.5 → 358.3 (+5.8 %) | 21.5 → 24.6 | 47.8 → 52.2 | 204.0 → 215.7 |
| `89e43e8` → `e578829` (natural line height), load 4.4–6.7 | 255.4 → 270.0 (+5.7 %) | 359.6 → 368.6 (+2.5 %) | 24.9 → 32.8 | 53.5 → 60.3 | 216.1 → 216.4 |

- **The iterative rewrite costs 4–6 %** of a settled read: about 3–4 ms of layout (the
  frame stack, the `Call` and `LayoutFrame` values that carry a `PenNode` each) and about
  12 ms of parse on 5000 nodes (`ChildDeferringDecoder`). It bought reading a 200-deep
  tree without `SIGBUS`. Diffuse, no single hot spot; not worth unwinding.
- **Natural line height costs 3–6 %**, all of it layout, and it is a correctness change
  (Pen parity) that happened to land in the same window. `PenTextMeasurer.measureCFAttributedString`
  now typesets every text twice — `CTFramesetterSuggestFrameSizeWithConstraints` for the
  width and `CTFramesetterCreateFrame` (`lineCount(of:width:)`) for the line count. Taking
  the width from the frame's lines would drop one pass, but whether a line's typographic
  width matches the suggested frame width (trailing whitespace, rounding) is exactly the
  kind of question the MAE gates exist to answer, so it is filed rather than built here.

The end-to-end binary shows the sum: `scripts/perf-binary --config release --reps 7`,
back to back at load 6.5–6.8, `tree woodcase-app.pen` 207.2 ms at `936a89d` and 231.7 ms
at main (+11.8 %; process start-up and output included).

**Verdict:** real, and just under the leaf's ~10 % line in process, just over it end to
end — but it is two causes of about 5 % each, one of them a correctness fix, and neither
has a small, clearly safe fix. No code changed. The `tree` budgets now have 8–10 %
headroom (271.7 / 300, 370.0 / 400), which is the thing to watch.

## U7wvkV — the PenExtras capture

```sh
# Interleaved, 5 rounds, debug:
WOODCASE_TEST_PROFILE=1 swift test --filter PerformanceBudgets.TreeTests 2>&1 \
  | grep -E 'BUDGET|PROFILE'
```

`aa4f0dd` (the direct parent of `1e6aeae`) against `1e6aeae`, debug, load 4.1–4.9:

| Budget | `aa4f0dd` | `1e6aeae` | change |
|---|---|---|---|
| `tree` `woodcase-app.pen` | 460.8 ms | 479.4 ms | +4.0 % |
| `tree` synthetic 5000 | 760.5 ms | 805.0 ms | +5.9 % |
| parse stage, synthetic | 203.9 ms | 232.7 ms | +14 % (29 ms) |
| parse stage, `woodcase-app.pen` | 24.2 ms | 26.6 ms | +10 % |

The 1212 ms that filed the leaf was load (293); the quiet figure is 805 ms, inside the
1000 ms debug limit. The capture costs about 6 µs a node in debug. The fix the leaf
proposed — skip the capture when a node has no unclaimed keys — is **already in**:
`PenExtras.capture` returns before allocating anything when every key is claimed. What is
left is listing the keys (`container(keyedBy: DynamicCodingKey.self).allKeys`) and one
set lookup per key, which a key-count comparison would not avoid, since the count is
read from the same key list. No fix built.

## Tdgxuz — the write-then-read pair

```sh
WOODCASE_SCRIPT_PERF=/Users/ben/git/Woodcase/local/tirekick.pen \
  swift test [-c release] --filter ScriptWritePerformanceTests 2>&1 | grep WRITE-READ
```

Run twice per configuration (each run 3 repetitions), minimum of 6 samples; 956 rows.
Debug at load 6.7–10.4, release at 4.7–7.6.

| 100 operations | debug | each | release | each |
|---|---|---|---|---|
| writes only | 828.1 ms | 8.3 ms | 394.0 ms | 3.9 ms |
| reads only | 2479.8 ms | 24.8 ms | 1652.3 ms | 16.5 ms |
| pairs | 41420.1 ms | **414.2 ms** | 20095.6 ms | **201.0 ms** |

The recorded 581.7 ms was loaded; quiet it is 414.2 ms debug, 201.0 ms release. **Still
over budget**: a hundred-pair loop is 41 s debug, 20 s release. Incremental settling
remains the named optimization and was not built.

The writes-only row rose from 72.4 ms to 828.1 ms, and it is not the writes: since
`265d1eb` (2026-09-08) `ScriptRunner.run` settles the document at the start of every
run for the root-overlap baseline and again at the end of a run that wrote
(`recordOverlaps`), so the row is two settles plus well under a millisecond a write.

## gh42Xb — the `shot` binary row

```sh
swift build -c release && swift build
scripts/perf-binary --config release --reps 7
scripts/perf-binary --config debug --reps 7
```

Load 5.2–5.3, minimum of 7:

| Command | release | debug |
|---|---|---|
| start-up floor | 10.2 ms | 12.6 ms |
| `tree woodcase-app.pen` | 230.8 ms | 378.1 ms |
| `set woodcase-app.pen` | 401.9 ms | 694.3 ms |
| `shot kit.lib.pen` | 187.9 ms | 216.3 ms |

## A finding on the way: `woodcase set` costs four times its budget

The binary's `set woodcase-app.pen` is 401.9 ms release against the in-process `set`
budget's 110.5 ms (limit 200 ms). It was 123.6 ms on 2026-08-30 and already 357.8 ms at
`936a89d`. `SetCommand.run` calls `RootOverlapWarnings.pairs(in:)` before the edit and
`RootOverlapWarnings.lines(since:in:file:)` after it, and each builds a whole
`SettledTree` (`RootOverlap.roots(in:)`), so every `set` settles the document twice to
answer whether two roots now overlap. `add`, `move`, `copy` and `apply` do the same. The
budget test times `PenFileTransaction` + `BatchApplier` only, so it cannot see this.
Filed as its own leaf.
