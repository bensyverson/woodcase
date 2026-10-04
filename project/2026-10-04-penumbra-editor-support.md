# 2026-10-04 — What Penumbra's editor push needs from Woodcase

**Status:** draft for Ben's review. Nothing is imported yet.\
**Requested by:** Penumbra's [2026-10-04-editor-vision.md](../../Penumbra/project/2026-10-04-editor-vision.md). Read its §2 rulings first.

Penumbra is becoming a full .pen editor. A human and agents edit the same file at the same time. The agents use the `woodcase` CLI, and Penumbra edits on the canvas. Most of the work that makes that sound belongs in Woodcase, because the CLI, the viewer and any future consumer need it too. Each task below says **what** is needed and **why**. **How** is Woodcase's call, including names, verbs and file layout. Penumbra pins each task with a contract leaf labeled `upstream`: a contract test of exactly the behavior Penumbra relies on.

## Ben's rulings that bind Woodcase

- **One edit funnel.** Every edit enters through one Woodcase type: local edits, external file merges, remote CRDT ops, and undo/redo.
- **Three histories, one job each.** The activity log records who did what. The CRDT merges live edits between humans. macOS file versions hold snapshots. Undo is per-author, and it never reverts another author's edit; a property changed since by someone else is kept.
- **External writes merge rather than reload.** That includes agents that rewrite a .pen file wholesale without the CLI.
- **Woodcase validates values on write,** for the CLI and editors alike. Loading stays lenient.
- **Agents' reads become events.** Penumbra shows them. They also answer the diagnostic question "did it look before it changed this?".
- **Woodcase owns the post-it convention and its default look,** and RapidPro must match it pixel for pixel.
- **Connectors get arrowheads and elbow routing.** Woodcase and RapidPro must render them identically.
- **Edits inside an instance are overrides by default.** An x/y override on an in-flow child is refused.

## Findings this plan rests on

These come from research on 2026-10-04 at Woodcase main. File references are relative to `Sources/Woodcase` unless they name another target.

- **`ActivityEvent` records inverses, ids, paths and the revision, but not the forward operation or its values** (Files/ActivityEvent.swift:76-121; Files/ActivityRecorder.swift:96-114). It can't replay a merge, and an agent can't see *what* Ben changed.
- **There is no document diff.** Nothing turns (old, new) into `[EditOperation]`. `PropertyDiff` returns key-path sets. `NodeDiffer` serves codegen only.
- **Inverses are state snapshots** (Editing/EditableDocument+Inverse.swift):
  - `updateCommon` and `updateKind` restore whole structs;
  - move and delete restore absolute indices;
  - override inverses restore the whole prior map.

  Correct for linear undo only. After interleaved foreign edits they revert those edits.
- **Detach inverses are left incomplete in two places.**
  - `completeDetachingDeleteInverse` has no callers.
  - `ActivityRecorder` records `prepareInverse` output with no completion step, so `rm --detach` logs a partial inverse.

  Detach also mints random ids (Editing/EditableDocument+Detach.swift:108).
- **`woodcase set`'s checks are internal to the CLI.** Authoring checks, coercion and slot rewrite live in `BatchApplier`'s internal planner (Batch/BatchApplier+Plan.swift). An editor can't call it.
- **There are no numeric ranges, units or variable checks on write.** An undefined or mistyped `$var` binding is accepted and surfaces only as lint (Lint/DocumentLinter.swift:269-277).
- **An x/y override on an in-flow child is accepted, stored and ignored by layout** (PenLayoutEngine+FlexLayout.swift:104-105).
- **The override-state queries are internal or missing.** There is no public "is this property overridden on this expanded node". There is no public map from an expanded id back to a `ResolvedNodeAddress`; `expandedID(of:)` goes the other way. `patchedDefinitionNode`, `componentRoot(ofInstance:)` and `overridableDescendantKeys` are internal.
- **`FileWatcher`, `PresenceTracker` and the watch-and-log matching live in WoodcaseViewer,** which is not a library product (Package.swift:11-23). `FileWatcher` silently drops a path whose re-arm `open` fails mid-rename (WoodcaseViewer/Files/FileWatcher.swift:111-112, 137-138).
- **Read verbs log nothing and take no identity** (PenFileTransaction.read). The log's invariants assume every row is a write: `LogLineage`'s newest event, the undo walk, and the viewer's attribution.
- **The agent's side is hard to use.** `woodcase activity` filters to `$WOODCASE_AS` by default, so an agent sees only its own events. It has no exclude-self filter, no resumable "since" cursor, and `--follow` blocks forever.
- **`NoteData` holds only `content`,** and so do `PromptData` and `ContextData`. Layout gives them 0×0. Nothing draws them. See c41x's [whiteboard doc](../../c41x/project/2026-10-04-whiteboard.md) "Woodcase gaps" 1–6 and 10.
- **The attributed-string builder for text is internal** (Rendering/PenTextRenderer.swift:87). RapidPro keeps its own copy, and Penumbra's caret engine would make a third.
- **There is no public SVG writer for `PenPath`.** `PenShapeOutline.svgPathData` is internal.
- **Layout is incremental only at root granularity.** A dirty root re-lays out its whole subtree.
- **The CRDT is solid but not ready for a relay.** It has about 260 tests, but it is wired into nothing. It has no causal buffering or dedupe: an op that arrives before its target node is dropped (Sync/CRDTDocument+RemoteProcessing.swift:13). It has no coverage for fonts, `version` or extras, and no identity↔`PeerID` mapping. StateTransfer builds the store from the local file but the CRDT from the remote snapshot.

## Plan

`job import project/2026-10-04-penumbra-editor-support.md --dry-run` first.

```yaml
tasks:
  - title: "Penumbra editor support"
    desc: |
      Work Penumbra's editor push needs from Woodcase. Context, rulings and findings: project/2026-10-04-penumbra-editor-support.md and ../Penumbra/project/2026-10-04-editor-vision.md. Each task states what and why; how (types, verbs, files) is Woodcase's call. These are high-level tasks, not dispatchable leaves: before building one, plan it into leaves under it in this tracker (all of the parent's work in its leaves), with its own red/green tests. Penumbra pins each capability with a contract test (Penumbra's "Upstream contracts" leaves list exactly what it relies on — read the matching one before planning). When a task is done, tell the Penumbra integrator so the matching `upstream` contract in Penumbra's tracker can start. Keep the library cross-platform; Darwin-only pieces go behind availability/#if.
    labels: [penumbra-editor]
    children:
      - title: "DocumentSession: one edit funnel with per-author undo"
        ref: session
        desc: |
          One entry point for every edit to a document: local intents, external file merges (via the three-way diff task), remote CRDT ops, and undo/redo for the local author. Penumbra will adopt it as its only mutation path; the CLI's PenFileTransaction/ActivityRecorder path should be expressible through it too, so there is one funnel, not two. It owns the EditableDocument, the optional CRDTDocument, the local Author (identity name as written by --as, plus a PeerID — the log and the CRDT need an explicit mapping) and per-author undo/redo stacks. Each submission returns a value describing what happened: applied ops with completed inverses, invalidation subjects (expose what subjects(of:) computes, plus structural/full flags), resulting revision, activity events to append (local origin), CRDT ops to broadcast, whether it is undoable and dirtying.

          Undo must be per-author and safe under interleaved foreign edits: inverses become property-granular (setProperties per key rather than whole common/kind structs; moves relative to a sibling anchor rather than an absolute index; override inverses per key), each checked by revision. A key another author changed since is kept, and the result says which keys were kept and by whom so the app can tell the user. Fix along the way: detach inverses are completed everywhere (completeDetachingDeleteInverse has no callers; ActivityRecorder logs partial detach inverses for `rm --detach`), and detach ids are deterministic so peers and undo agree.
        criteria:
          - "Every edit origin enters through one public submit API and returns one change value"
          - "Undo after an interleaved edit by another author keeps that author's values and reports them"
          - "Detach and detaching delete round-trip through undo, in the app path and in the log"
      - title: "Three-way document diff into edit operations"
        ref: diff
        desc: |
          Turn (base, ours, theirs) .pen documents into the minimal EditOperations that bring ours up to theirs while keeping our unwritten changes — so an editor merges a file that changed on disk instead of reloading. Must handle any writer: the CLI, an agent rewriting the file wholesale, Pen.app. Key by node id; prune subtrees with equal revision(of:); emit insert/delete/move (parent or index)/property ops plus variables, imports, themes, fonts; order ops so they apply validly (creates before moves into them, deletes last, instance guards); define what happens for an id deleted and re-created, a type change, and true conflicts (same key changed on both sides — say which wins and report it). Fuzz it: random edit pairs must converge to theirs-plus-ours.
        criteria:
          - "Merging a wholesale rewrite yields ops whose application equals the rewritten file"
          - "Unwritten local changes survive a merge, with conflicts reported"
          - "Unchanged subtrees cost no diff work"
      - title: "PenFileTransaction as an app's save path"
        ref: app-save
        blockedBy: [session]
        desc: |
          Penumbra will save each committed change through PenFileTransaction under the user's identity, so agents see `ben` instead of an unattributed `external` row (today Penumbra writes compact JSON with no lock and no log, which also blocks `woodcase undo`). Make that a supported public path for a long-lived app process: commit a session change (ops, inverses, identity) under the lock, write pretty JSON as the CLI does, append the activity rows, and report the new revision so the app's merge base advances. It must coexist with the app's NSFilePresenter and debounced writes.
        criteria:
          - "An app can commit a change under the lock and it logs under its identity"
          - "A subsequent woodcase undo by an agent is not blocked by the app's save"
      - title: "Public edit planner shared by the CLI and editors"
        ref: planner
        desc: |
          Today what `woodcase set`/`override` check (address resolution, refusing writes inside instances, deep metadata keys, authoring checks, coercion, slot-fill rewrite, parameter routing, divergence notes) lives in BatchApplier's internal planner, and Penumbra's drag writes whole-struct updateCommon that skips the codec. Expose one public planner: an intent (set, bind/unbind variable, override, reset override) plus a target (including an instance descendant) → ops plus divergences or a refusal. It decides set vs override from the resolved address, so "edits inside an instance are overrides" is a Woodcase rule. The CLI uses the same planner.
        criteria:
          - "The CLI's set/override verbs and an editor produce identical ops for the same intent"
          - "An edit to an instance descendant plans as an override"
      - title: "Validate values on write: ranges, units, variables, in-flow position"
        ref: constraints
        blockedBy: [planner]
        desc: |
          Ben's ruling: Woodcase refuses invalid values on write, for the CLI and editors alike; loading stays lenient. Add constraints to property shapes (range, step, unit, non-negative — opacity 0–1, sizes ≥ 0, lineHeight as a multiple, etc.), refuse binding an undefined variable or one of the wrong type, refuse an x/y override (or set) on an in-flow child that layout would ignore (suggest absolute positioning), and decide whether cross-field lint checks (fill-in-fit-parent, per-side stroke on shape) become refusals. `woodcase schema` prints the constraints. Refusals carry stable codes and the expected form so an inspector can show them inline.
        criteria:
          - "An out-of-range value and a mistyped variable binding are refused with a stable code"
          - "woodcase schema shows each property's constraints"
          - "Opening a file with out-of-range values still works"
      - title: "Property-editor and override-state queries"
        ref: queries
        blockedBy: [planner]
        desc: |
          What an inspector needs to generate and drive controls without its own copy of the format: a per-node-type list of editable fields with their control-relevant shape (forms, spellings, nested tables, constraints, bindable variable type); compatible variables for a property; for an expanded node, its resolved address (a public inverse of expandedID(of:), including the instance root), its source node, and which properties are overridden there. Some pieces exist internally (patchedDefinitionNode, componentRoot(ofInstance:), overridableDescendantKeys, ComponentProvenance) or partly (inspectComponent).
        criteria:
          - "Given an expanded descendant id, an editor can learn its address and its overridden properties"
          - "An editor can list the variables that may bind to a given property"
      - title: "Follow a file and its activity in the library"
        ref: follow
        desc: |
          Penumbra needs what WoodcaseViewer has — watching a .pen file, following the project's activity log for it, matching writes to log events, and presence — without depending on the viewer (not a library product). Move or rebuild the reusable parts into the library (FileWatcher and PresenceTracker have no viewer dependencies; ChangeCoordinator's matching needs splitting from rendering/SSE) and keep the viewer on them. Fix: FileWatcher silently drops a path whose re-arm open fails mid-rename (delete-then-recreate writers). Presence should become node-level (latest nodes changed/viewed per identity) so editors can place agent cursors.
        criteria:
          - "A library consumer can follow one file's changes and attributed events"
          - "A delete-then-recreate write keeps the file watched"
          - "Presence reports each identity's latest nodes"
      - title: "Agent view events"
        ref: views
        blockedBy: [follow]
        desc: |
          Log which nodes an identity read, and at which revision, when it reads through the CLI (tree, find, get, shot, render…), so editors can show what an agent looked at and so "did it look before it changed this?" is answerable. Read verbs need an identity (`--as` / $WOODCASE_AS); unattributed reads log nothing. Keep views out of the write-history invariants (LogLineage's newest event, the undo walk, ChangeCoordinator attribution) — a separate stream beside activity.jsonl is the suggested shape; coalesce repeated reads of one revision by one identity.
        criteria:
          - "An attributed woodcase tree or get records the viewed nodes and revision"
          - "Undo, lineage and change attribution behave exactly as before"
      - title: "Agent change feed: what changed since my last look"
        ref: feed
        desc: |
          The other half of Penumbra's demo: an agent edits a screen, Ben reacts in Penumbra (post-its, copy edits, moves), and the agent picks up his changes and responds. Today an agent can't do that well: `woodcase activity` filters to $WOODCASE_AS by default (it sees only its own events), has no exclude-self filter and no resumable since-cursor, `--follow` blocks forever, and events carry no forward op or values, so "Ben changed the title to X" must be reconstructed by reading the file. Design how a turn-based agent asks "what changed since my last look, by others, with the new values" — a new verb, options on activity, forward ops in the log, or something else. Ben's ruling: Woodcase decides. Document it in the agent-facing docs.
        criteria:
          - "A turn-based agent can list others' changes since its last look, with new values, and resume next turn"
          - "Ben's Penumbra edits appear attributed to his identity"
      - title: "Sized notes, the post-it convention and the Post-it look"
        ref: notes
        desc: |
          Notes are how humans and agents talk on a board. Give note (and prompt, context — Pen: Note extends Entity, Size, TextStyle) width, height and the text style, in the model, schema, codec, override paths and layout (today 0×0). Own the post-it convention: metadata {type: postit, kind: question|answer|reference, author, state: open|resolved, leaf, stage} with typed spellings, documented for agents (c41x's board uses it; see c41x project/2026-10-04-whiteboard.md). Own the default look, drawn by the CG renderer and specified precisely enough for RapidPro to match: a flat square, soft shadow, slight corner radius, Post-it yellow by default and tintable to any color (a property the inspector can set — decide where it lives), the note's text inset at its text style, the author in lighter text bottom-left, resolved notes visibly resolved, and a default size (200×200) when the file says 0×0. Author is whoever created the note or edited it after copying. Also c41x gap 6: metadata keys as tree/find columns and a post-it listing (`--postits` or a notes verb).
        criteria:
          - "add/set accept a note's width, height and text style and tree reports its size"
          - "shot and render draw every post-it on c41x-system.pen with author and tint"
          - "The convention's kinds and states are refused when misspelled"
      - title: "One public text-layout API"
        ref: text
        desc: |
          Penumbra needs caret positions, glyph hit-testing and selection rects that match rendering exactly. The attributed-string builder is internal (Rendering/PenTextRenderer.swift:87) and RapidPro carries its own copy; a caret engine would be a third. Expose one API: for a text node (and a note) in a box, the attributed string and placed lines (PenTextLines) that every renderer uses, plus what an editor needs (string index ↔ point, line rects). RapidPro will adopt it.
        criteria:
          - "CG rendering, RapidPro and an editor caret can share one layout call"
      - title: "Layout below root granularity"
        ref: layout
        desc: |
          Live reorder previews and live resize must hold 60 Hz on an M1 Air on a large board. Today a dirty root re-lays out its whole subtree. Provide incremental layout at node granularity and a hypothetical layout (e.g. "this stack with child X removed and inserted at index i", "this node at size w×h") that is cheap and doesn't mutate the document. Measure with named commands.
        criteria:
          - "A hypothetical reorder in a stack of a 2,000-node board lays out in well under a frame in Release"
      - title: "Connectors: arrowheads, elbow routing, follow-along"
        ref: connectors
        desc: |
          Ben's ruling: connectors get arrowheads and elbow routing (format extensions beyond Pen — Pen.app drops connection nodes anyway), with Woodcase and RapidPro rendering identically. Add them to the model, schema and CG renderer. Editors need a node → connections index (so moving a card invalidates its connectors) and the connector's segment/route as a hit-test and painted extent (today its layout rect is meaningless). Also c41x gaps 3–5: endpoints in tree/find, no artboard placement for connections, and drawing connections in shot/render.
        criteria:
          - "A connection can declare arrowheads and elbow routing, and the CG renderer draws them"
          - "Given a moved node, the library lists the connections to redraw"
          - "shot and render draw connections whose endpoints fall in the rect"
      - title: "Path serializer and anchor model"
        ref: path
        desc: |
          Penumbra's pen tool writes paths. There is no public PenPath → SVG writer (PenShapeOutline's is internal). Provide one, and an anchor/handle model (corner/smooth/broken handles) that round-trips geometry, with helpers to normalize geometry into node-local coordinates and compute x/y/width/height/viewBox (a zero-height viewBox is unusable — straight paths must omit it).
        criteria:
          - "Any parsed path re-serializes to geometry that parses back equal"
          - "An anchor list converts to geometry and back"
      - title: "Image fill crop units"
        ref: crop
        desc: |
          c41x gap 10: an image fill crops only through `transform`, in fractions of the box, found by trial ([W/cw, 0, 0, H/ch, -cx/cw, -cy/ch] shows pixel rect (cx, cy, cw, ch) of a W×H image). Penumbra's crop UI will write it. Document the units in schema output, or add a crop rect helper, so writers can't get it wrong.
        criteria:
          - "The transform's units are documented where agents and editors read them"
      - title: "CRDT ready for a relay"
        ref: crdt
        blockedBy: [session]
        desc: |
          Ben wants the relay built to prove the CRDT in practice. Gaps: no causal delivery buffer or dedupe (an op arriving before its target node is dropped, Sync/CRDTDocument+RemoteProcessing.swift:13 — the April plan put buffering in Penumbra; it belongs with the session now), no coverage for fonts/version/extras, no identity↔PeerID mapping, StateTransfer builds the store from the local file but the CRDT from the remote snapshot, offline replay of ops whose afterPositionIDs the snapshot doesn't know. Text content is LWW per node — acceptable for now; say so in the docs.
        criteria:
          - "Ops delivered out of order or twice converge identically"
          - "Fonts and document extras round-trip through the CRDT"
```
