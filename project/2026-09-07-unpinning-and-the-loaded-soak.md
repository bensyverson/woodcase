# Un-pinning the editing layer, and what it does to the loaded soak

*2026-09-07. Finding, measured on leaf `111nTf`. Status: measured; no action taken.*

Removing `@MainActor` from the editing layer leaves our own code exactly as fast and
makes the **WebKit-dependent tests much slower under artificial CPU saturation**. The
suite still passes; `scripts/soak-tests --timeout 280 --load 6` does not, because the
watchdog now sits inside a tail that the un-pin widened. This note records the numbers so
the next reader does not mistake a watchdog for a hang.

## What was seen

The first loaded soak of the un-pinned branch reported 1/3:

```
scripts/soak-tests 3 local/111nTf-soak.log --load 6 --timeout 280     # the branch
run 1  exit=0   85s  passed after 73.0s
run 2  exit=124 295s TIMEOUT after 280s
run 3  exit=124 293s TIMEOUT after 280s
```

The same command on `main`, in the same worktree, minutes later: 3/3 (75 s, 77 s, 223 s).
So the difference was real and it was this leaf's.

`sample` of the wedged test host showed **no Woodcase frames at all** — the third face in
`project/gotchas.md` (2026-08-31). That reads as a suspended `await`, and cost an hour.
It was not one. Raising only the watchdog turns every "wedge" into a pass:

```
scripts/soak-tests 3 local/111nTf-soak2.log --load 6 --timeout 600    # the branch
run 1  exit=0  202s  passed after 199.5s
run 2  exit=0  588s  passed after 586.0s
run 3  exit=0   78s  passed after  76.1s
```

The idle sample is explained by the browser tests' own `waitFor`, which polls with
`Task.sleep`: a sleeping task has no thread, so a suite that is merely *slow* in that
phase looks exactly like one that is hung.

## Where the time is, and where it is not

With every WebKit-dependent test skipped, the two sides are indistinguishable — three
loaded runs each, same machine, back to back
(`swift test --quiet --skip Browser --skip WebView --skip Viewer`, six `yes > /dev/null`):

| | run 1 | run 2 | run 3 |
|---|---|---|---|
| un-pinned | 56.3 s | 56.8 s | 57.6 s |
| `main` | 58.4 s | 57.7 s | 56.7 s |

So the un-pin costs our own code nothing. The whole difference is in the WebKit tests,
and it is a *tail*, not a shift. Full-suite wall clock under `--load 6`, every sample
taken on this machine today:

- `main` — 75, 77, 223, 66, 68, 68 s (one slow run in six)
- un-pinned — 73, 81, 199, 268, 278, 586 s, plus two runs cut at the 280 s watchdog
  (six slow runs in eight)

The single slowest test in a slow run is a WebView regression case: *"ActionButton
renders visually similar in both pipelines"* took **228 s** in one run against about 30 s
in a fast one.

## The mechanism, and why it is not a bug

Best-supported reading: the pin was an accidental **throttle**. With `EditableDocument`
on the main actor, the viewer's page building took turns with WebKit's own main-thread
work on one actor. Un-pinned, page building runs on the cooperative pool *in parallel*
with WebKit — and on a machine already saturated by six spinners it takes CPU the WebKit
main thread used to have to itself. Every browser round trip stretches, and a test built
of twenty of them stretches twenty times.

In production that is the change working: page building no longer blocks the main thread.
It is only under `--load 6` — deliberate over-saturation — that losing the throttle costs
more than parallelism buys. Not proven: no experiment isolated the viewer's page building
from the rest of the un-pin.

## What to do with this

Nothing was changed for it. Two consequences for the next reader:

- **`--timeout 280` is too tight for `--load 6` on this machine.** The script's default
  is now 600 s (raised at integration, 2026-09-07); read a `TIMEOUT` line as "measure it
  again with a longer watchdog" before reading it as a hang.
- **A sample with no frames of ours does not prove a hang.** Check whether the phase in
  flight is one that polls with `Task.sleep` first; that is what `waitFor` does.

## Reproducing

Branch and `main` in the same worktree, `swift build --build-tests` first so the build is
not in the measurement, then `scripts/soak-tests 3 <log> --load 6 --timeout 600`. Per-test
durations come from a run *without* `--quiet`; the slowest are
`grep -oE 'Test "[^"]+" passed after [0-9.]+ seconds' <log> | sort -rn -t'"' -k3`.
