# Woodcase project docs

The index of Woodcase's written history: plans, design docs, rulings, findings about Pen, and the records sessions leave behind. `AGENTS.md` names only what nearly every session needs; open this file when a task enters an area you haven't worked in this session, and read the doc its hook points to before you start.

Each dated document (`YYYY-MM-DD-title.md`) is a point-in-time record. A later doc or an in-place correction can overrule it, so check the doc's opening for a status or correction note before citing it. How the code works lives in the [DocC catalog](../Sources/Woodcase/Documentation.docc/); the [README](../README.md) lists every article.

## Before you touch an area

- [WoodcaseEditor.md](../Sources/Woodcase/Documentation.docc/WoodcaseEditor.md) — read before editing a .pen file from a shell: the read–write–verify loop, addressing, property paths, batches, revision tokens and undo. `woodcase help design` is the same primer in the terminal.
- [WoodcaseScripting.md](../Sources/Woodcase/Documentation.docc/WoodcaseScripting.md) — read before touching `Sources/WoodcaseScripting/`, or the `js` or `find` verbs: the contract a `woodcase js` program runs under, the `doc` declaration, the `ScriptHost` API, the watchdog. `woodcase help js` is the same contract in the terminal.
- [WoodcaseActivityLog.md](../Sources/Woodcase/Documentation.docc/WoodcaseActivityLog.md) — read before touching `Sources/Woodcase/Files/`, `Follow/` or `Feed/`: the activity log's wire format, `views.jsonl`, following a file, and `woodcase changes` (`woodcase help recipes` ▸ TAKING TURNS).
- [DESIGN.md](../DESIGN.md) — read before styling anything in `WoodcaseViewer`; it moves together with `ViewerStylesheet.swift`.
- [agents/cli-design.md](agents/cli-design.md) — read before adding or changing a CLI verb, its output or its errors.
- [2026-10-20-natural-paths-for-woodcase-properties.md](2026-10-20-natural-paths-for-woodcase-properties.md) — read before adding a Woodcase-owned property stored in metadata: the ruling that it is set by a natural path everywhere.
- [2026-10-05-pen-bundle-format.md](2026-10-05-pen-bundle-format.md) — read before touching `.umbra` bundles, imports across bundles, or what a bundle holds.
- [2026-08-31-guards-and-echo.md](2026-08-31-guards-and-echo.md) — read before touching revision guards or concurrent writes to one file.
- [2026-10-21-batch-property-writes.md](2026-10-21-batch-property-writes.md) and [2026-10-19-proportional-scale.md](2026-10-19-proportional-scale.md) — read before changing batch writes or proportional scale in the edit planner.
- [2026-10-05-edit-cost-proportional.md](2026-10-05-edit-cost-proportional.md) — read before making an edit, remote apply or in-component edit cost more than its change.
- [2026-03-28-codegen-design.md](2026-03-28-codegen-design.md) — read before changing the React emitter: why codegen is deterministic and how it maps the format.
- [2026-09-26-fixture-provenance-audit.md](2026-09-26-fixture-provenance-audit.md) — read before adding a fixture that came from Pen (follow its correction).
- [2026-08-29-sleepyhollow-harness.md](2026-08-29-sleepyhollow-harness.md) — read before touching the WebView regression harness.

## Current plans

Each `job` root's description names the plan it executes (`job status` lists the roots). The plans behind today's roots:

- [2026-10-04-penumbra-editor-support.md](2026-10-04-penumbra-editor-support.md) — what Penumbra's editor push needs from Woodcase, with [Penumbra's editor vision](../../Penumbra/project/2026-10-04-editor-vision.md). Its design docs, each read before its task: [document session](2026-10-04-document-session-design.md), [follow, views and feed](2026-10-04-follow-views-feed-design.md), [post-its](2026-10-04-post-it-design.md) (revised by Penumbra's [notes, comments and spans](../../Penumbra/project/2026-10-11-notes-comments-and-spans.md)), [sub-root layout](2026-10-04-sub-root-layout-design.md), [text layout](2026-10-04-text-layout-design.md) and [three-way diff](2026-10-04-three-way-diff-design.md).
- [2026-09-26-swiftui-emitter-plan.md](2026-09-26-swiftui-emitter-plan.md) — the SwiftUI emitter, from its [feasibility report](2026-09-26-swiftui-codegen-feasibility.md); read before touching the SwiftUI emitter. Its design choices: [components](2026-09-26-swiftui-components.md), [roles and states](2026-09-27-swiftui-roles-and-states.md), [themes](2026-09-27-swiftui-themes.md), [instance calls](2026-09-28-swiftui-instance-calls.md), [line height](2026-09-26-swiftui-line-height.md), [text in flex](2026-09-26-swiftui-text-in-flex.md).
- [2026-10-23-pen-cli-0.3.13.md](2026-10-23-pen-cli-0.3.13.md) and [2026-10-08-pen-1.2.16-format-2.21.md](2026-10-08-pen-1.2.16-format-2.21.md) — read before following Pen's latest format or behavior changes.
- [2026-10-10-cli-agent-audit.md](2026-10-10-cli-agent-audit.md) — read before work on agent-readable CLI output.
- [2026-09-30-intro-deck.md](2026-09-30-intro-deck.md) — the intro deck (`2026-09-30-intro-deck/` holds its briefs and prompts).

## Rulings

- [2026-10-20-apple-platforms-only.md](2026-10-20-apple-platforms-only.md) — why Woodcase targets only macOS and iOS.
- [2026-09-26-mae-margin-rule.md](2026-09-26-mae-margin-rule.md) — read before setting or loosening an MAE threshold.
- [2026-10-21-build-test-loop-baseline.md](2026-10-21-build-test-loop-baseline.md) — why release-only timing lives in `WoodcaseBench`, not the test target.
- [2026-10-14-slot-semantics.md](2026-10-14-slot-semantics.md) — read before slot work: a slot's list suggests components; it does not restrict types.

## What Pen does

Findings about Pen's own behavior, measured through the `pen` CLI. Read the one on your topic before changing how Woodcase matches Pen. Several carry a 2026-10-23 correction where an earlier version read Pen.app's bundle; follow the correction.

- [2026-09-27-fidelity-gaps.md](2026-09-27-fidelity-gaps.md) — where Woodcase draws differently from Pen; start here for any fidelity question.
- [2026-09-28-geometry-model.md](2026-09-28-geometry-model.md) and [2026-08-29-absolute-fit-content-and-the-group-anchor.md](2026-08-29-absolute-fit-content-and-the-group-anchor.md) — read before changing node rects, groups or `fit_content`.
- Paints and effects: [fill clip and domain](2026-09-26-fill-clip-and-domain.md), [gradient geometry and per-side strokes](2026-09-26-gradient-geometry-and-per-side-strokes.md), [stroke paints](2026-09-26-stroke-paints.md), [text and stroke fills](2026-09-26-text-and-stroke-fills.md), [mesh gradients](2026-09-26-mesh-gradients.md), [missing-image checkerboard](2026-09-27-pen-missing-image-checkerboard.md).
- Files: [what Pen drops from a file](2026-09-26-what-pen-drops-from-a-file.md), [canonical form](2026-08-29-pen-canonical-form.md), [import resolution](2026-09-26-pen-import-resolution.md), [slot override keys](2026-09-26-slot-override-keys.md), [what Pen keeps on a note](2026-10-11-what-pen-keeps-on-a-note.md), [font faces](2026-09-28-pen-font-faces.md).
- **Format versions** — `YYYY-MM-DD-pen-<app version>-*.md` (such as `2026-10-03-pen-1.2.15-format-2.20.md` and `2026-09-26-pen-1.2.14-compatibility.md`) and [the 2.17 migration](2026-08-29-pen-2.17-migration.md): what each Pen release changed and how Woodcase followed.
- [2026-03-23-pencil-rendering-quirks.md](2026-03-23-pencil-rendering-quirks.md) — where Pen's renderer departs from SVG and CSS, as first found.
- [2026-08-29-pen-cli.md](2026-08-29-pen-cli.md) and [2026-08-29-pen-mcp-tire-kick.md](2026-08-29-pen-mcp-tire-kick.md) — the `pen` CLI and Pen's MCP, first tried.

## Agent experience reports

Read before changing the CLI or the scripting host's surface: what agents actually did with them. [Five agents, one .pen](2026-08-31-woodcase-concurrent-dx.md), [Quill mobile](2026-09-01-quill-mobile-agents-dx.md), [landing-page pilot](2026-09-10-ufti-pilot-feedback.md), [Jobs mobile dashboard](2026-08-30-jobs-mobile-dashboard-experience.md), [Figma MCP vs Woodcase](2026-10-13-figma-mcp-vs-woodcase-experience.md), the scripting host [plan](2026-09-07-scripting-host.md) and its trials ([one](2026-09-08-scripting-host-trial.md), [two](2026-09-08-scripting-host-trial-2.md)), and [teach the CLI what it does](2026-09-02-teach-the-cli-what-it-does.md).

## Suite, performance and debugging

- [2026-09-28-suite-speed.md](2026-09-28-suite-speed.md) and [2026-09-27-quiet-machine-measurements.md](2026-09-27-quiet-machine-measurements.md) — read before work on suite time or a performance budget.
- Hangs and flakes, each a post-mortem with its cause: [suite stability](2026-08-30-suite-stability.md), [the page that never answers](2026-09-26-the-page-that-never-answers.md), [the await that cannot resume](2026-08-31-the-await-that-cannot-resume.md), [load-shaped budgets](2026-08-31-load-shaped-budgets.md), [the fontd wedge](2026-10-20-fontd-wedge-and-the-layout-gate.md), [follow is a value](2026-08-31-follow-is-a-value.md). Read the matching one before chasing a wedged or flaky `swift test`.
- [2026-09-26-debug-stack-depth.md](2026-09-26-debug-stack-depth.md) and [2026-09-27-expanded-tree-cost.md](2026-09-27-expanded-tree-cost.md) — read before adding recursion to the read pipeline or expanding instances on a large document.
- [2026-09-26-sandbox-font-downloads.md](2026-09-26-sandbox-font-downloads.md) — why Google Font downloads fail inside the Claude Code sandbox.
- [2026-08-30-release-only-ctfont-sigtrap.md](2026-08-30-release-only-ctfont-sigtrap.md) and [2026-08-30-two-mains-in-one-test-bundle.md](2026-08-30-two-mains-in-one-test-bundle.md) — release-build traps.

## Records sessions leave

None of these is listed one by one; find them by name.

- **Handoffs** — `*-handoff.md` (for example `2026-09-27-wave-eleven-handoff.md`, `2026-09-07-scripting-host-handoff.md`): what landed, what's open, where to start. The newest of a series is where to pick it up.
- **Prototype and mockup folders** — `project/YYYY-MM-DD-topic/` (viewer prototype, mobile viewer, intro deck, note look), linked from the doc of the same name.
- **Fixtures** — `fixtures/`: small `.pen` files a finding reproduces with.

## Processes and standing files

- [gotchas.md](gotchas.md) — project traps and rule feedback; read at session start.
- [backlog.md](backlog.md) — work parked on purpose, and what would revive it.
- [agents/](agents/) — [delegation](agents/delegation.md), [jobs](agents/jobs.md), [harness](agents/harness.md) and [CLI design](agents/cli-design.md): read each when the situational table in `AGENTS.md` says to.

## Reference material outside `project/`

- `../local/` (gitignored, so absent from a worktree; use the main checkout's): the .pen spec `Pen-Format.md`, Pen's published schemas — `Pen-Schema-2.21.md` (current), `Pen-Schema-2.17.md` (with a section on what Pen writes beyond the schema, still true), `Pen-Schema.js` (2.10) and `Pen-Schema-v2.js` (2.17 dev docs) — and `swiftui-docs/`, Apple's API docs offline (`scripts/swiftui-api`; see [scripts/README.md](../scripts/README.md)).
- [Penumbra's project index](../../Penumbra/project/README.md) and [RapidPro's](../../RapidPro/project/README.md) — the sibling repos' docs.

## Early history

The March and April plans (`2026-03-*`, `2026-04-*`) built the parser, renderer, codegen research, React emitter and CRDT core. Read them only for the reasoning behind a part that still works that way; the DocC articles describe the code as it is now. The August viewer and editor docs (`2026-08-29-viewer-*`, `2026-08-30-*`) likewise record how the viewer and CLI came to be.
