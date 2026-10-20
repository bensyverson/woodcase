# The fontd wedge, and gating layout (2026-10-20)

**Finding (leaf 6StvbE, which is issue Wz8Lz8 in another place).** A test host sometimes
waits forever on a synchronous XPC reply from `fontd` that never comes, while `fontd`
itself sits idle. It is not a lock-order inversion in Woodcase: every waiting thread is
behind a reply `fontd` does not send. It forms when several of the process's Core Text
calls reach `fontd` at once, and Woodcase let them, because ``FontRegistryGate`` covered
font *resolution* but not *typesetting*, which reaches `fontd` by itself. Gating every
Core Text layout call in Woodcase stopped it in the soak below. The gate's earlier
explanation — the cooperative pool running out of threads — was wrong, and is corrected
in [2026-08-30-suite-stability.md](2026-08-30-suite-stability.md).

## What the hang was

w-zstd's sample of the hung `WoodcaseViewerTests` host (pid 76103, 2026-10-19, three
identical `sample` runs 21:54:33–44; the file was in `/private/tmp`, not kept) had eight
cooperative threads:

- **one inside the gate**: `fontFamilyAvailable` → `CTFontCopyFamilyName` →
  `XTCopyPropertiesForFont` → `xpc_connection_send_message_with_reply_sync` → `mach_msg`;
- **one outside it**: `ChangedArtboardsTests.expandedCopiesCount` →
  `PenTextMeasurer.typesetLines` → `CTTypesetterCreateWithAttributedString` →
  `TBaseFont::DetermineFontFlags` → `XTCopyPropertiesForFont` → the same wait;
- **six on the gate's `NSRecursiveLock`**, in `resolveFontUncached`.

The main thread was idle in `CFRunLoopRun`, a workqueue thread idle, no font registration
in flight. `log show --predicate 'process == "fontd"'` shows `fontd` opening the peer
connection for 76103 at 20:39:52.624 and logging nothing more for it until the kill at
21:54:49 — 75 minutes with two requests unanswered. So the brief's suspicion, an inversion
between resolution and registration, does not hold: no thread held one lock and wanted
another.

## Reproducing it

Standalone programs did not reproduce it (`swiftc -O`, sandbox off, load 30–60): 24
threads typesetting all 1318 installed faces cold, 5 of 5 finished; the same with a thread
registering and unregistering `.process` fonts throughout, 6 of 6; 300 fresh processes
whose first Core Text calls came from 8 threads at once, 300 of 300.

The test suite did. `PenTextGeometryTests` lays out text needing a fallback face (emoji, a
mathematical script letter) from parallel cases; it was `.serialized` for Wz8Lz8. With
`.serialized` removed, in fresh test hosts four at a time
(`scripts/host-soak <rounds> WoodcaseTests PenTextGeometryTests <outdir>`, 60 s limit):

| layout | hosts | hung | load (1 min) |
| --- | --- | --- | --- |
| ungated (before) | 60 | **9** | 31–150 |
| ungated `PenTextLines` only, rest gated | 60 | **3** | 93–95 |
| every layout call gated | 180 | **0** | 90–121 |
| every layout call gated, `host-soak` | 120 | **0** | 30–78 |

(The first three rows ran an ad-hoc copy of the same loop before it became
`scripts/host-soak`.) The hung hosts' samples show the fallback path —
`CTFramesetterCreateWithAttributedString` → `TFontCascade::CreateFallback` →
`XTCopyFontWithName` or `XTCopyPropertiesForFont` → `xpc_connection_send_message_with_reply_sync` —
with the other threads either in the same wait or queued on Core Text's own
`_CTFontFallbacksArray` lock behind it. Several hosts had **one** request in flight, so it
is not that `fontd` refuses a second request; something about several in flight at once,
earlier, leaves one unanswered. `sample` of `fontd` during three hangs found it all but
idle: its main thread in `sigsuspend`, its workers parked, at most one tearing down another
client's connection, and no thread working on a request. The request is lost, not slow. That is Apple's bug to fix, and worth a Feedback; the
samples were not kept, and `scripts/host-soak` against an ungated build writes fresh ones,
`fontd`'s included.

The viewer slice that hung on 2026-10-19
(`scripts/host-soak 20 WoodcaseViewerTests "ChangedArtboardsTests|InstanceSelectionTests|RenderCache" <outdir>`)
passed 80 of 80 after the fix (load 33–77); it had passed 56 of 56 before the fix too (beside 56 hosts of the font suites, load 50–80), so it is not the
evidence — `PenTextGeometryTests` is.

## The fix

Every Core Text layout call in Woodcase now goes through ``FontRegistryGate``:
``PenTextMeasurer``'s typesetter and framesetter (`typesetLines`, `framedLines`,
`measureCFAttributedString`), ``PenTextLines``' framesetter (every drawn text, and
``PenTextLayout``), ``PenIconGlyph/line(color:)`` and the browser placeholder's label.
`PenTextGeometryTests` is no longer `.serialized`; its parallel cases are the check.
`FontRegistryGateLayoutTests` pins the mechanism deterministically: it holds the gate on
one thread and expects a measurement and a drawing layout, their fonts already resolved,
to wait for it — red before (both finished while it was held), green after, every wait
bounded.

**The cost.** Text layout inside one process is serialized. Layout in Woodcase is mostly
one document on one thread, so this only costs where several threads lay text out at
once. RapidPro's `TextRasterizer` sets text through `PenTextLayout`, so it is gated now,
and RapidPro's sources start no concurrent work of their own today (no task groups or
`concurrentPerform`, checked 2026-10-20). Calls to Core Text's layout made outside
Woodcase are outside the gate, which is internal: RapidPro's browser-placeholder label
(`CTLineCreateWithAttributedString`) and Penumbra's overlay readouts and comments. On one
thread beside Woodcase's gated work they can still put a second request in flight.

## Open

- **J4saCp** (something holds the cooperative pool during the full suite) — not resolved
  here, and not shown to be this. Six pool threads queued on the gate during a wedge is one
  way the pool fills, but J4saCp's symptom is a late `Task.sleep`, not a hang.
- **Wz8Lz8** — this is its fix; close it with 6StvbE if the integrator agrees.
- A public way for RapidPro and Penumbra to take the gate for their own Core Text layout,
  if either lays text out on several threads.
