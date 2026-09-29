# 2026-09-27 — Handoff, wave eight: SwiftUI catalog and slots, CG line height, React transforms

The eighth integrator session, following [wave seven](2026-09-27-wave-seven-handoff.md). Start with `job orient`,
then this doc. Wave eight was dispatched the night before and stopped when the disk filled (ENOSPC); this session
freed space, fixed the leak behind it, resumed the five agents in their original worktrees (all Opus, `-j 3`,
three dispatched first and two once those builds were warm), and integrated all five. Full suite on the combined
tree: 3614 + 1017 + 494 + 163 tests, green (`swift test -j 3 --quiet`). Everything is pushed; no worktrees remain.

## What landed

| Commit | Leaf | What |
|---|---|---|
| `8694ab0` | `HxAVGX` | Test runs sweep the `pen-exports-<pid>` folders of exited processes on first use (109 of them held 2.4 GB); the latest run's folder stays for debugging, `WOODCASE_KEEP_TEST_OUTPUT=1` keeps all |
| `f493a82` | `PlHnG2`, `ifNKJL`, `x3UuVF` | SwiftUI unfilled text is `.foregroundStyle(.clear)` (Pen draws it as nothing, both schemes; the harness renders dark boards now); mesh color variables read through the theme; `PenMeshColor.hexColor(penMesh:)` reads mesh colors as Pen does (30 strings pinned by `render-mesh-colors.pen`). **Breaking:** `PenMeshColor.init?(hex:)` removed |
| `6b2b11b` | `mkPpjZ` | React transforms are valid CSS, negated (Pen turns CCW), flips before turn, `transformOrigin: "0 0"` for nodes placed by `x`/`y` (`TransformPivot`). Designer states 0.026/0.009/0.039 in WebKit (were 11–27). The node's own rotation had the same wrong sign. `ReactHarnessBuilder` now inlines `states.css` |
| `9d8cdc8` | `26chl8` | SwiftUI slots: a generic `@ViewBuilder` parameter per slot frame, `<Component><Slot>Default` views, one constrained init, filled instances as trailing-closure calls; `codegen-slots.pen` rendered 0.22–1.62 |
| `8aba33c` | `0QZeR3` | SwiftUI kit catalog: `#Preview` per state × theme variant, `PenCatalog`/`PenCatalogSheet`/`PenCatalogThemes`, a `<Module>Catalog` executable (`--snapshot <png>`). Rows wrap at the window's width after Ben saw a right-edge cutoff |
| `f1a199b` | `HVBKsf` | CG text: optical sizing off except the SF Pro fallback (the larger cause), per-line rounded pitch and rounded half-leading baseline via `PenTextLines`, one typesetting pass per draw. Line-height boards 0.07–1.57 (were 5.5–13.4); SwiftUI's line-height ceilings gone; CG text gates tightened |

RapidPro `18076f3`: files `UzE2Ou` (TextRasterizer should adopt `PenTextLines`) and commits its `.jobs/` log, which
had never been committed. Its uncommitted `.agents.yaml` and two agent docs were left as found.

## Decisions (two-way doors)

- **Unfilled text draws clear, not black** — measured: Pen draws a text or icon with no enabled fill as nothing.
  Raised with Ben twice; no objection. CG still draws it black until `PRFPX5`.
- **Mesh colors follow Pen's parser, malformed ones included** (`red` → `#00EEDD`, 4/5-digit → transparent);
  lint names every color Pen misreads.
- **React pivots:** anchor for free-positioned nodes (exact), center for flex children (closest; Pen grows the
  slot to the turned bounds and CSS cannot). Documented, not filed.
- **One constrained init for all slots**, not one per subset (2ⁿ); a partial fill passes the other defaults.
- **Catalog pieces are support templates**, and `main.swift` is `#if os(macOS)`.
- **Page-name casing** (`FilledCard` → `Filledcard`) filed as `K68yo3` instead of kept as a gotcha.

## Still open

- `PRFPX5` CG draws unfilled text/icons as nothing (unblocked; lift the two `swiftui-color-scheme-unfilled` 0.0 ceilings after).
- `K68yo3` page type names keep inner capitals (moves React and SwiftUI goldens).
- `oozXCK` SwiftUI packaging and docs (unblocked by the catalog), then `Dc3tN9` churn guard.
- Performance: `cHuvso` (measurer still typesets twice), `MdCEmo`, `Tdgxuz`.
- RapidPro `UzE2Ou`.
- The catalog window itself has not been seen by a human since the scroll fix; a build from `main` is at
  `local/catalog-demo` (`swift run WoodcaseAppCatalog`).

## Traps hit this session

- **Finder's folder size lied.** It showed Woodcase at 130 GB; `du` said 11 GB. SwiftPM's
  `CompilationCache.noindex/…/data.v1` is a sparse file reporting 24 GB logical per worktree. Measure with `du`.
- **Merged branches, fresh collisions.** Catalog and slots were each green; merged, the new slot render batch
  would have copied the catalog's `main.swift` beside its own. Caught by reading the diff, and by generating
  and building the merged `codegen-slots` package with the CLI — the render batches deliberately compile the
  library only, so no test compiles a catalog for a slotted document. Gotcha updated.
- **Closing an agent's leaf needs its claim released first**, under the agent's identity (see gotchas, `rule:`).
- **`git worktree remove --force` leaves the directory** when a build or a launched app still holds files in it
  (`Directory not empty`); `rm -rf` the remainder, then `git worktree prune`.
- **Briefs were wrong again in the usual places**: the mesh parse model (wrong for 6/8 digits), "every layout
  golden moves" (four did), the line-height cause (optical size was the bigger half), the pivot hint (the gotcha
  describes CG, not CSS), "nested `<Slot>Default`" (unnameable in the generic's own where-clause). Every agent
  answered the brief-errors question.
