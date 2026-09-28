# 2026-09-27 — Handoff, wave seven: SwiftUI components, themes, states and mesh; SleepyHollow green on macOS 27

The seventh integrator session, following [wave six](2026-09-26-wave-six-handoff.md). Start with `job orient`, then this
doc. Sixteen agents ran (all Opus), at most five Swift builds at once, all integrated. Ben was away for most of it and
asked for two-way decisions to be made and reported; they are listed under *Decisions made unattended*.

## What landed

Woodcase (all pushed):

| Commit | Leaf | What |
|---|---|---|
| `ac494e6` | `SGjFZi`, `0qUbof` | CG casts a group's outer and inner shadows from its descendants' opaque silhouette, reached through groups only; `PenGroupShadowSnapshotTests` (7 boards × 2 scales, worst 0.44, from 6.7) |
| `4b4af8f` | `sH43HM` | SwiftUI groups: a top-leading `ZStack` anchored at the group's origin, shadows cast from a silhouette the page writes in black (`penGroupShadows`); blur2 111.38 → 8.35, blur3 16.42 → 10.38 (background blur only) |
| `1449771` | `FPHQQ5` | SwiftUI components: view structs with typed props, instances as calls or inlined copies (`InstanceOverrides`, target-neutral); goldens over woodcase-app and pages ([choices](2026-09-26-swiftui-components.md)) |
| `89e43e8` | `WBOels`, `ZCCotT` | render-strokes-and-paths' reference was a stale March export from an older Pen; re-exported, CG 5.114 → 0.027, SwiftUI 5.117 → 0.034. ZCCotT's premise was empty |
| `e578829` | `hwCwvs` | Inter committed as a test font (OFL); CG sets natural line height as Pen rounds it (`PenTextMeasurer.naturalLineHeight`) — the fallback face had hidden a real rounding bug |
| `0bc1044` | `PhTQsf` | SwiftUI themes: typed `PenTheme` in the environment, `.penTheme(axis:)` for context nodes, light/dark axes bridged to `colorScheme` ([choices](2026-09-27-swiftui-themes.md)) |
| `190be37` | `wXirUH` | SwiftUI roles and states as `Button`/`Toggle`/`TextField`/`Menu`+`Picker`/tab bar; designer states drawn from their frames; smart defaults from `StateEffect`; transform deltas typed (`DeltaTransform`); new fixture `codegen-states.pen` ([choices](2026-09-27-swiftui-roles-and-states.md)) |
| `abbc30d` | `rlSTe9` | SwiftUI mesh: `PenMeshGradient`, a `ShapeStyle` resolving to a native `MeshGradient` subdivided 8×8 per Pen cell; all 8 boards 0.18–0.83 at CG + 1.0, fold included |
| `e72f982` | `HjUFQT`, `C6c5nu`, `97Dngc` | SwiftUI `fill_container` gets a zero minimum; flat lines draw (`penOutset`); support type names reserved; natural line pitch as Pen rounds it. The 14 woodcase-app screens, light and dark: 1.28–2.46 (were 2.96–6.20) |
| `4564016` | — | SleepyHollow pinned to `5fd352a`; its hook gotcha retired |

RapidPro `3ee9bd4`: a group's inner shadow inside its descendants' silhouette (group-inner 6.6 → 0.44/0.20).

SleepyHollow `5fd352a` (committed through its own hook, which passes again): the link records the SDK it was built
against, not the macOS 12 floor, which is what made WebKit print the inspection notice
([finding](../../SleepyHollow/project/2026-09-26-old-sdk-inspection-notice.md)); an idle page is held at foreground
priority for shot, pdf and archive (WebKit drops a windowless page's content process from 31 to 4 after ~1 s idle,
[finding](../../SleepyHollow/project/2026-09-26-idle-page-throttling.md)); deadlines for archive and cookie calls
(**breaking**: `currentCookies()` throws); test budgets sized for a loaded machine.

## Decisions made unattended (two-way doors)

- **SwiftUI mesh writes `PenMeshGradient(…)`, not a literal `MeshGradient(…)` call.** It resolves to a native
  `MeshGradient`, so the ruling's intent (native, no raster, themeable) holds; the literal call cannot meet the
  criterion (malpha 4.96, mfold 7.14). Reversible by recording those two as baselines.
- **Only a light/dark axis bridges to `colorScheme`**; banking's `scheme: day/night` is carried as a theme axis without
  the bridge.
- **Designer states are drawn from their whole frames**, not from deltas (exact, but no animation between states).
- **A link role is a `Button(action:)`**, not a `Link` (woodcase-app's links are in-app actions).
- **Instances inline when a call can't draw what Pen draws** — stricter than React, which drops properties of an
  override a prop only partly carries. React left unchanged.
- **The SleepyHollow fixes landed as one commit**, since three leaves shared files and the hook could only pass with all
  of them.

## Still open

- SwiftUI: `0QZeR3` kit catalog (blocks packaging `oozXCK`, then churn guard `Dc3tN9`), `26chl8` slots as
  `@ViewBuilder`, `PlHnG2` unfilled text draws `.primary` (white in dark mode), `ifNKJL` mesh colours through the theme.
- `HVBKsf` CG places explicit line heights unlike Pen (the render-text-line-height boards score 5.5–13.4 in CG).
- `mkPpjZ` React's designer-state rotate/flip is invalid CSS and never draws.
- Quiet-machine measurements landed (`7ddef2f`, [findings](2026-09-27-quiet-machine-measurements.md)): the settled `tree` read grew 7–9 % since 936a89d, half from the iterative rewrite and half from natural line height typesetting each text twice (`cHuvso`); the binary's `set` settles the tree twice for its overlap warnings (`MdCEmo`); the write-then-read pair is 414 ms debug / 201 ms release, still over budget (`Tdgxuz`, open).

## Traps hit this session

- **Two branches green alone, red together.** Themes and states each passed; merged, a control's state faces read the
  theme without declaring it, so the generated Swift would not compile, and a clean *text* merge of the goldens hid it.
  Regenerate goldens after merging emitter branches and read the diff; `SwiftUIEmitterThemeTests.everyReadIsDeclared`
  now pins the invariant.
- **Briefs were wrong in the usual places**: "raise the floor" (the SDK version was misrecorded), "every time" (only
  under load), "fallback face or rounding?" (rounding, hidden by the fallback), "the state fixtures" (none existed),
  "plain MeshGradient lands within 3.5" (not on translucent meshes). Every agent answered the brief-errors question.
- **Load reached 200–316 with five agents**; the known WebKit trio failed under it and passed alone every time.
