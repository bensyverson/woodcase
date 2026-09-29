//
//  ViewerStylesheet.swift
//  WoodcaseViewer
//

import Foundation

/// The viewer's stylesheet, served at `/viewer.css`.
///
/// A Swift string rather than a resource file, because `woodcase serve` is one
/// executable and a viewer that had to locate its own assets on disk is one more thing
/// that breaks when the binary moves.
///
/// ## The tokens
///
/// Everything color is a `--v-*` custom property defined twice: once for light, once
/// inside `prefers-color-scheme: dark`. The site's own light and dark follow the
/// operating system; the *file's* theme axes are a separate control in the top bar, and
/// the two never share a switch.
///
/// `--v-chrome` is set back from `--v-panel` on purpose. The panels are where things
/// happen — a row lighting up, a marker appearing — and they need a surround to happen
/// against, or every in-action state is white on white.
///
/// Identity color arrives as `--v-actor` on the element that needs it, never as a
/// class: the color is hashed, so there is no finite set of classes to write. Its ink
/// rides beside it as `--v-actor-ink`, for the same reason.
///
/// ## The inks
///
/// Four tokens end in `-ink`, and they all answer one question: what is legible *on*
/// this fill. `--v-actor-ink` is written per element (the fill is hashed);
/// `--v-faint-ink` letters the presence stack's `+N` disc; `--v-accent-fill-ink`
/// letters a persistent word on the accent fill — the true bool pill, the selection
/// box's tag — dark in both schemes, because the accent is bright in both (the same
/// 0.179 pivot the avatar makes answers black); `--v-accent-ink` is the odd one out, the
/// accent dark enough to be *read* as text rather than seen as a fill — the accent itself
/// stays where it is, because it is also a fill and moving it would drag every dot, box
/// and pill with it. Ben's rulings, 2026-09-02: AA (4.5:1) is the bar for text that
/// carries meaning, `faint` is exempt as scaffolding, and white on the accent is allowed
/// only for a transient flash (the copied chip and button). `DESIGN.md` § *Colors*
/// carries the numbers.
public enum ViewerStylesheet {
    /// The stylesheet's text: the viewer's own rules, then the preview pages'.
    ///
    /// Two strings joined rather than one literal because the literal is already past a
    /// thousand lines, and the preview frames are a self-contained section that reads
    /// better beside the vocabulary it implements — see ``previewRules`` in
    /// `ViewerStylesheet+Previews.swift`.
    public static let css = core + previewRules

    /// Everything the served pages of a document use.
    static let core = """
    :root {
      --v-bg: #F6F5F1;
      --v-chrome: #ECEAE3;
      --v-panel: #FFFFFF;
      --v-line: #E2DFD6;
      --v-text: #1B1B18;
      --v-muted: #65625A;
      --v-faint: #A5A096;
      --v-faint-ink: #1B1B18;
      --v-accent: #2FBF6F;
      --v-accent-ink: #1D7745;
      --v-accent-fill-ink: #1B1B18;
      --v-warn: #AC4C1B;
      --v-select: rgba(47, 191, 111, 0.12);
      --v-shadow: 0 1px 2px rgba(27, 27, 24, 0.06);
      --v-sans: -apple-system, BlinkMacSystemFont, "Inter", system-ui, sans-serif;
      --v-mono: ui-monospace, "JetBrains Mono", SFMono-Regular, Menlo, monospace;
      --v-indent: 0.85rem;
      --v-mark-component: #6A45FC;
      --v-mark-instance: #1D68C8;
      --v-mark-slot: #18766B;
      color-scheme: light dark;
    }

    @media (prefers-color-scheme: dark) {
      :root {
        --v-bg: #161615;
        --v-chrome: #232321;
        --v-panel: #1D1D1B;
        --v-line: #33322F;
        --v-text: #EDEBE4;
        --v-muted: #9E9991;
        --v-faint: #6A665E;
        --v-faint-ink: #FFFFFF;
        --v-accent: #3ED483;
        --v-accent-ink: #3ED483;
        --v-accent-fill-ink: #161615;
        --v-warn: #E08A4E;
        --v-select: rgba(62, 212, 131, 0.16);
        --v-shadow: none;
        --v-mark-component: #A594FF;
        --v-mark-instance: #6BA6F5;
        --v-mark-slot: #4FC8B8;
      }
    }

    * { box-sizing: border-box; }

    html, body { height: 100%; }

    body.v-body {
      margin: 0;
      background: var(--v-bg);
      color: var(--v-text);
      font: 13px/1.45 var(--v-sans);
      display: grid;
      grid-template-rows: 44px minmax(0, 1fr);
      overflow: hidden;
    }

    .v-mono, code, pre { font-family: var(--v-mono); }

    /* ---- top bar ---- */

    .v-topbar {
      display: flex;
      align-items: center;
      gap: 0.9rem;
      padding: 0 0.9rem;
      background: var(--v-chrome);
      border-bottom: 1px solid var(--v-line);
    }

    /* The brand is the way back to the root, which is why no crumb says "Files". */
    .v-brand {
      font-family: var(--v-mono); font-weight: 600;
      color: var(--v-text); text-decoration: none; flex: none;
    }
    .v-brand:hover { color: var(--v-accent); }

    .v-crumbs { display: flex; align-items: center; gap: 0.35rem; flex: 1; min-width: 0; }
    .v-crumb { color: var(--v-muted); text-decoration: none; }
    .v-crumb:hover { color: var(--v-text); }
    .v-crumb.is-current { color: var(--v-text); font-weight: 600; }
    .v-crumb-sep { color: var(--v-faint); }

    .v-topbar-controls { display: flex; align-items: center; gap: 0.9rem; }

    .v-live {
      font-family: var(--v-mono);
      font-size: 11px;
      color: var(--v-muted);
      display: inline-flex;
      align-items: center;
      gap: 0.35rem;
    }
    .v-live::before {
      content: "";
      width: 7px; height: 7px; border-radius: 50%;
      background: var(--v-faint);
    }
    /* The word takes the accent's ink, the dot takes the accent: one is read, the other
       is seen, and 11px of #2FBF6F on chrome is 1.98:1. */
    .v-live[data-state="live"] { color: var(--v-accent-ink); }
    .v-live[data-state="live"]::before { background: var(--v-accent); }
    .v-live[data-state="lost"] { color: var(--v-warn); }
    .v-live[data-state="lost"]::before { background: var(--v-warn); }

    /* Every label is server-rendered and the state picks one, so the script never writes
       a word of text — and the badge can never go amber while still reading "live". */
    .v-live-label { display: none; }
    .v-live[data-state="connecting"] .v-live-label[data-state="connecting"],
    .v-live[data-state="live"] .v-live-label[data-state="live"],
    .v-live[data-state="lost"] .v-live-label[data-state="lost"] { display: inline; }

    /* ---- avatars ---- */

    .v-avatar {
      display: inline-flex;
      align-items: center;
      justify-content: center;
      border-radius: 50%;
      background: var(--v-actor, var(--v-faint));
      /* The disc names its own ink: at a fixed 48% lightness a hashed hue can be a
         bright green or a deep blue, and white is legible on only one of them. The
         fallback is white for a disc drawn with no identity behind it. */
      color: var(--v-actor-ink, #FFFFFF);
      font-family: var(--v-sans);
      font-weight: 700;
      line-height: 1;
      flex: none;
    }
    .v-avatar-small { width: 15px; height: 15px; font-size: 9px; }
    .v-avatar-medium { width: 20px; height: 20px; font-size: 11px; }
    .v-avatar-large { width: 28px; height: 28px; font-size: 14px; }
    /* Not a hashed hue but `faint`, so it names its ink from the palette rather than
       inheriting whichever identity's the stack last wrote. */
    .v-avatar-more { background: var(--v-faint); color: var(--v-faint-ink); font-size: 9px; }

    /* ---- presence ---- */

    .v-presence { position: relative; }
    .v-presence-summary {
      display: flex; align-items: center; gap: 0.5rem;
      cursor: pointer; list-style: none;
    }
    .v-presence-summary::-webkit-details-marker { display: none; }
    .v-presence-stack { display: inline-flex; }
    .v-presence-stack .v-avatar + .v-avatar { margin-left: -7px; }
    .v-presence-stack .v-avatar { box-shadow: 0 0 0 2px var(--v-chrome); }
    .v-presence-note { font-size: 11px; color: var(--v-muted); }
    /* A handle is an `--as` address, so it is mono wherever it is spelled out — here in
       the summary and the expanded list both, matching the activity row. */
    .v-presence-name { font-family: var(--v-mono); }
    .v-presence-list {
      position: absolute; right: 0; top: calc(100% + 6px); z-index: 20;
      margin: 0; padding: 0.4rem; list-style: none; min-width: 15rem;
      background: var(--v-panel); border: 1px solid var(--v-line);
      border-radius: 6px; box-shadow: var(--v-shadow);
    }
    .v-presence-item {
      display: grid; grid-template-columns: 20px 1fr auto auto;
      gap: 0.5rem; align-items: center; padding: 0.25rem;
    }
    .v-presence-age, .v-presence-events { font-family: var(--v-mono); font-size: 11px; color: var(--v-muted); }

    /* ---- theme picker ---- */

    .v-theme { display: flex; align-items: center; gap: 0.5rem; }
    .v-theme-axis { display: inline-flex; align-items: center; gap: 0.3rem; margin: 0; }
    .v-theme-label { font-size: 11px; color: var(--v-muted); font-family: var(--v-mono); }
    .v-theme-select {
      font: 11px var(--v-mono); color: var(--v-text);
      background: var(--v-panel); border: 1px solid var(--v-line);
      border-radius: 4px; padding: 2px 4px;
    }
    .v-go {
      font: 11px var(--v-mono); padding: 2px 6px; cursor: pointer;
      background: var(--v-panel); color: var(--v-text);
      border: 1px solid var(--v-line); border-radius: 4px;
    }
    html[data-js="on"] .v-go { display: none; }

    /* ---- layout ---- */

    .v-main { min-height: 0; overflow: hidden; }

    .v-layout-artboard .v-main {
      display: grid;
      grid-template-columns: 340px minmax(0, 1fr) 320px;
      gap: 1px;
      background: var(--v-line);
    }
    .v-side { background: var(--v-panel); overflow-y: auto; min-height: 0; }
    .v-side-left { display: flex; flex-direction: column; }
    .v-side-left .v-outline { flex: 1; min-height: 0; overflow-y: auto; }

    .v-canvas {
      background: var(--v-bg);
      display: grid; grid-template-rows: minmax(0, 1fr);
      /* One explicit track each way. An implicit `auto` track sizes to its content, and
         the content here can be a bird's-eye plane 40 000 points wide — which would
         stretch the pane, and with it the whole page, rather than scrolling inside it.
         The canvas is sized by the pane, never by what is in it. */
      grid-template-columns: minmax(0, 1fr);
      overflow: hidden; min-height: 0; min-width: 0;
    }
    .v-render-scroll { overflow: auto; min-height: 0; display: grid; place-content: center; }

    .v-layout-dashboard .v-main { overflow-y: auto; padding: 1.6rem 2rem; }
    .v-layout-empty .v-main { display: grid; place-items: center; }

    /* ---- panels ---- */

    .v-panel { border-top: 1px solid var(--v-line); }
    .v-panel:first-child { border-top: 0; }
    .v-panel-head {
      display: flex; align-items: baseline; justify-content: space-between;
      gap: 0.5rem; padding: 0.5rem 0.75rem;
      position: sticky; top: 0; background: var(--v-panel); z-index: 5;
    }
    .v-panel-title {
      margin: 0; font-size: 10px; font-weight: 700;
      letter-spacing: 0.09em; text-transform: uppercase; color: var(--v-muted);
    }
    .v-panel-note { font-family: var(--v-mono); font-size: 11px; color: var(--v-faint); }
    .v-empty-note { margin: 0; padding: 0.5rem 0.75rem; color: var(--v-faint); }
    .v-empty-note code { font-size: 11px; }

    .v-row { display: flex; align-items: center; gap: 0.4rem; }

    /* ---- outline ---- */

    .v-outline-row {
      padding: 2px 0.75rem 2px calc(0.75rem + var(--v-depth, 0) * var(--v-indent));
      color: inherit; text-decoration: none;
      border-left: 3px solid transparent;
      font-size: 12px;
    }
    .v-outline-row:hover { background: var(--v-chrome); }
    .v-outline-row.is-selected { background: var(--v-select); }
    .v-outline-row.is-touched { border-left-color: var(--v-actor); }
    .v-glyph { width: 1em; color: var(--v-faint); font-family: var(--v-mono); flex: none; }
    .v-outline-name { flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .v-outline-name.is-unnamed { color: var(--v-faint); font-family: var(--v-mono); }
    .v-outline-rect, .v-outline-id, .v-outline-children {
      font-family: var(--v-mono); font-size: 11px; color: var(--v-faint); flex: none;
    }
    .v-clip { color: var(--v-warn); flex: none; }

    /* ---- kind marks: component definition, instance, slot ---- */

    .v-kind-mark {
      display: inline-flex; align-items: center; gap: 0.2rem;
      padding: 1px 5px; border-radius: 999px;
      font-family: var(--v-mono); font-size: 9px; font-weight: 600;
      letter-spacing: 0.02em; text-transform: uppercase;
      flex: none; line-height: 1.5;
      border: 1px solid color-mix(in srgb, var(--v-mark, var(--v-faint)) 45%, transparent);
      color: var(--v-mark, var(--v-muted));
      background: color-mix(in srgb, var(--v-mark, var(--v-faint)) 12%, transparent);
    }
    .v-kind-component { --v-mark: var(--v-mark-component); }
    .v-kind-instance { --v-mark: var(--v-mark-instance); }
    .v-kind-slot { --v-mark: var(--v-mark-slot); }
    .v-kind-glyph { font-size: 8px; }

    /* ---- id chips ---- */

    .v-id-chip {
      position: relative;
      display: inline-flex; align-items: center;
      padding: 2px 6px; border-radius: 4px;
      font-family: var(--v-mono); font-size: 11px; font-weight: 500;
      color: var(--v-muted); background: var(--v-line);
      cursor: pointer; flex: none;
    }
    .v-id-chip:hover { background: var(--v-faint); color: var(--v-panel); }
    .v-id-chip.is-copied { background: var(--v-accent); color: #FFFFFF; }

    /* The copied flash, on a chip and on the footer's copy button: both words are
       server-rendered and the script flips `is-copied`. The resting word stays in flow
       and keeps the box's width; `copied` is laid over it, so nothing beside it moves. */
    .v-copied {
      position: absolute; inset: 0;
      display: flex; align-items: center; justify-content: center;
      visibility: hidden;
    }
    .is-copied > .v-copied { visibility: visible; }
    .is-copied > .v-id-chip-id, .is-copied > .v-copy-label { visibility: hidden; }

    /* ==== BEGIN disclosure glyph (eqwDy) ================================= */

    /* Shared by any expand/collapse control — the Variables pane's own toggle and each
       row's `<summary>` today, the Outline pane next. The box is sized well past the
       triangle it draws, for a comfortable click target; `currentColor` lets whichever
       control it sits in set its own color. Carries no direction of its own — a caller
       that starts open leaves it unrotated, one that starts closed rotates it -90deg by
       default and back to 0 on its own open state, entirely in that caller's rules. */
    .v-disclosure-glyph {
      display: inline-flex; align-items: center; justify-content: center;
      width: 18px; height: 18px; flex: none;
      color: var(--v-muted);
      transition: transform 0.15s ease;
    }
    .v-disclosure-glyph svg { width: 8px; height: 8px; display: block; }

    /* ==== END disclosure glyph (eqwDy) =================================== */

    /* ---- variables ---- */

    /* The toggle and the title are one flush-left group, so the title sits directly
       beside the disclosure control rather than floating away from it — `space-between`
       on `.v-panel-head` distributes its leftover width between *every* adjacent pair
       of its direct children, not just around the first and last, so the axes note on
       the right needs the toggle and title wrapped together as a single item. */
    .v-panel-head-title { display: flex; align-items: center; gap: 0.35rem; }

    .v-variables-toggle {
      appearance: none; border: 0; background: transparent; cursor: pointer;
      color: var(--v-muted); padding: 0; line-height: 1;
      transition: transform 0.15s ease;
    }
    .v-variables.is-collapsed .v-variables-toggle { transform: rotate(-90deg); }
    .v-variables.is-collapsed .v-variable-rows,
    .v-variables.is-collapsed .v-empty-note { display: none; }
    /* A block, not the `.v-row` flex it also wears: as a flex container the `<details>`
       set its summary and its hidden body side by side and spent a `gap` between them,
       so the summary could never be the row's full width. */
    .v-variable-row { display: block; font-size: 12px; }
    .v-variable-rows { max-height: 40vh; overflow-y: auto; }
    /* The full width of its row, said outright: a flex `<summary>` shrink-wrapped inside
       its `<details>`, and then a number's `flex: 1` had nothing to grow into and sat
       beside its own name instead of at the right edge. */
    .v-variable-summary {
      display: flex; align-items: center; gap: 0.4rem;
      width: 100%; box-sizing: border-box;
      padding: 2px 0.75rem; cursor: pointer; list-style: none;
    }
    .v-variable-summary::-webkit-details-marker { display: none; }
    /* The row's own glyph starts closed (pointing right) and opens to match the
       header's — same shape, rotated the other way by default. */
    .v-variable-summary .v-disclosure-glyph { transform: rotate(-90deg); }
    .v-variable-row[open] > .v-variable-summary .v-disclosure-glyph { transform: rotate(0deg); }
    .v-swatch {
      width: 11px; height: 11px; border-radius: 2px; flex: none;
      background: var(--v-swatch, transparent);
      border: 1px solid var(--v-line);
    }
    /* Only a color has a swatch. The slot stays, so every name starts on one column,
       but it draws nothing — an outlined empty box read as a color that failed. */
    .v-swatch.is-empty { visibility: hidden; }
    .v-variable-name { font-family: var(--v-mono); flex: none; }
    .v-variable-value {
      font-family: var(--v-mono); font-size: 11px; color: var(--v-muted);
      flex: 1; min-width: 0; overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    }
    .v-variable-value.v-variable-number { text-align: right; color: var(--v-text); }
    .v-variable-value.v-variable-string { font-family: var(--v-sans); color: var(--v-text); }
    .v-bool-pill {
      flex: none; text-align: center; border-radius: 999px; padding: 0 6px;
      background: var(--v-faint); color: var(--v-panel);
    }
    /* A persistent word on the accent fill takes the dark ink that fill is read in —
       white on it is 2.39:1, and only a flash may keep that (Ben, 2026-09-02). */
    .v-bool-pill[data-value="true"] { background: var(--v-accent); color: var(--v-accent-fill-ink); }
    .v-variable-age { font-family: var(--v-mono); font-size: 11px; color: var(--v-faint); flex: none; }
    .v-variable-detail { padding: 0.25rem 0.75rem 0.5rem 1.75rem; color: var(--v-muted); }

    /* One row per axis/mode, its two columns aligned down the table — the same grid
       pattern `.v-detail-row` uses for a node's properties, so a themed variable and a
       node's own detail read the same way. */
    .v-variant-table { margin-top: 0.3rem; display: grid; gap: 2px 0; }
    .v-variant-row {
      display: grid; grid-template-columns: minmax(4.5rem, auto) minmax(0, 1fr);
      gap: 0 0.6rem; align-items: center;
      font-family: var(--v-mono); font-size: 11px;
    }
    .v-variant-axis { color: var(--v-faint); }
    .v-variant-value {
      display: inline-flex; align-items: center; gap: 0.35rem;
      color: var(--v-text); overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    }

    /* ---- activity ---- */

    .v-activity-summary {
      display: grid;
      grid-template-columns: 3.2rem 15px 4.5rem 3rem minmax(0, 1fr);
      gap: 0.4rem; align-items: center;
      padding: 2px 0.75rem; cursor: pointer; list-style: none;
      font-size: 12px; white-space: nowrap;
    }
    .v-activity-summary::-webkit-details-marker { display: none; }
    .v-activity-row:hover { background: var(--v-chrome); }
    .v-activity-time { font-family: var(--v-mono); font-size: 11px; color: var(--v-faint); }
    .v-activity-identity { font-family: var(--v-mono); font-size: 11px; color: var(--v-muted); overflow: hidden; text-overflow: ellipsis; }
    .v-activity-verb { font-family: var(--v-mono); font-size: 11px; font-weight: 600; }
    /* The stand-in for a writer with no `--as`: faint, like the `#id` standing in for an
       unnamed node — the absence of a name, spelled out rather than left as a hole. */
    .v-activity-identity.is-unattributed, .v-presence-name.is-unattributed { color: var(--v-faint); }
    /* Front-truncated like every path: the RTL box puts the ellipsis at the head, so the
       node's name and the `+3` survive, and the `<bdi>` keeps the characters in written
       order. `text-align: left` keeps a path that fits where a left-to-right one sits;
       one that overflows is start-aligned regardless, which in RTL is what clips the head. */
    .v-activity-path {
      direction: rtl; text-align: left;
      overflow: hidden; text-overflow: ellipsis;
    }
    .v-activity-detail {
      padding: 0.3rem 0.75rem 0.6rem 4.4rem;
      font-family: var(--v-mono); font-size: 11px; color: var(--v-muted);
    }
    .v-activity-detail p { margin: 0.15rem 0; }
    .v-activity-nodes { margin: 0.2rem 0; padding-left: 1rem; }
    .v-activity-node-id { color: var(--v-faint); margin-left: 0.4rem; }

    /* ---- files ---- */

    .v-section-head { display: flex; align-items: flex-end; justify-content: space-between; gap: 1rem; }
    .v-section-title { margin: 0; font-size: 20px; }
    .v-section-subtitle { margin: 0.2rem 0 0; color: var(--v-muted); }
    .v-section-note { font-size: 11px; color: var(--v-faint); }
    .v-file-cards {
      margin-top: 0.9rem;
      display: grid; gap: 0.8rem;
      grid-template-columns: repeat(auto-fill, minmax(228px, 1fr));
    }
    .v-file-card {
      display: flex; flex-direction: column; gap: 0.45rem;
      padding: 0.5rem; color: inherit; text-decoration: none;
      background: var(--v-panel); border: 1px solid var(--v-line); border-radius: 8px;
      box-shadow: var(--v-shadow);
    }
    .v-file-card:hover { background: var(--v-chrome); border-color: var(--v-accent); }
    .v-file-thumb {
      display: flex; align-items: center; justify-content: center;
      height: 144px; padding: 0.4rem; border-radius: 5px;
      background: var(--v-chrome); overflow: hidden;
    }
    /* The render keeps its own aspect ratio inside a fixed box: artboards run from a
       402x874 phone to a 1440x900 desktop, and a grid of cards that each sized to their
       own artboard would be a staircase. */
    .v-file-shot {
      display: block; width: auto; height: auto;
      max-width: 100%; max-height: 100%; object-fit: contain;
    }
    .v-file-blank { font-size: 11px; color: var(--v-faint); }
    .v-file-identity { display: flex; flex-direction: column; min-width: 0; padding: 0 0.15rem; }
    .v-file-name { font-weight: 600; overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .v-file-path {
      font-size: 11px; color: var(--v-muted);
      overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
    }
    .v-file-foot { justify-content: space-between; padding: 0 0.15rem; font-size: 11px; }
    .v-file-count { color: var(--v-muted); flex: none; }
    .v-file-change { display: inline-flex; align-items: center; gap: 0.35rem; min-width: 0; }
    .v-file-when { color: var(--v-muted); white-space: nowrap; }
    .v-file-when.is-quiet { color: var(--v-faint); }
    .v-file-error { color: var(--v-warn); font-family: var(--v-mono); font-size: 11px; }
    .v-file-card.is-broken {
      background: color-mix(in srgb, var(--v-warn) 6%, var(--v-panel));
      border-color: color-mix(in srgb, var(--v-warn) 35%, var(--v-line));
    }
    .v-files + .v-activity { margin-top: 1.4rem; border: 1px solid var(--v-line); border-radius: 8px; background: var(--v-panel); }

    /* ---- the render and its overlay ---- */

    .v-render-region {
      display: grid; grid-template-rows: minmax(0, 1fr) auto;
      /* One explicit column with a zero minimum, for the same reason `.v-canvas`
         declares its tracks: the implicit `auto` column sizes to its items' intrinsic
         width, and the selection footer's — a nowrap path plus its fixed facts — can be
         wider than the pane, which blew the footer out past the canvas and clipped its
         copy button and steps behind this box's own `overflow: hidden`. */
      grid-template-columns: minmax(0, 1fr);
      min-height: 0; overflow: hidden;
    }
    .v-stage {
      position: relative;
      margin: 0.75rem;
      width: calc(var(--v-art-w) * var(--v-scale) * 1px);
      height: calc(var(--v-art-h) * var(--v-scale) * 1px);
      background: var(--v-panel);
      box-shadow: var(--v-shadow);
    }
    .v-render { display: block; width: 100%; height: 100%; }
    .v-overlay { position: absolute; inset: 0; pointer-events: none; }

    .v-box {
      position: absolute;
      left: calc(var(--v-x) * var(--v-scale) * 1px);
      top: calc(var(--v-y) * var(--v-scale) * 1px);
      width: calc(var(--v-w) * var(--v-scale) * 1px);
      height: calc(var(--v-h) * var(--v-scale) * 1px);
      border: 2px solid var(--v-accent);
      pointer-events: none;
    }
    .v-box.is-edit { border-color: var(--v-actor, var(--v-accent)); }
    .v-box.is-fading { opacity: 0; transition: opacity 1.2s ease-out; }
    .v-box.is-pinned { opacity: 1; transition: none; }

    .v-box-tag {
      position: absolute; left: -2px; bottom: 100%;
      display: inline-flex; align-items: center; gap: 0.3rem;
      padding: 1px 5px; border-radius: 3px 3px 0 0;
      font: 10px var(--v-mono); color: var(--v-accent-fill-ink);
      background: var(--v-accent); white-space: nowrap;
      pointer-events: auto; cursor: pointer;
      /* Capped at the artboard's right edge, measured from this node's own left — the
         box carries its rect as custom properties, so the cap follows the zoom. Without
         it a deep node's path ran over the neighboring pane. */
      max-width: calc((var(--v-art-w) - var(--v-x)) * var(--v-scale) * 1px + 4px);
    }
    /* The footer's front-truncation, worn by the tag: RTL box so the ellipsis eats the
       head and the tail that names the node survives; the <bdi> inside keeps the em
       dashes and parentheses in written order. */
    .v-box-path {
      min-width: 0;
      overflow: hidden; white-space: nowrap; text-overflow: ellipsis;
      direction: rtl;
    }
    /* The tag is drawn on the actor's hue, so its words take the actor's ink — the same
       pivot the disc inside it makes, or the tag would read white on a bright green. */
    .v-edit-tag { background: var(--v-actor, var(--v-accent)); color: var(--v-actor-ink, #FFFFFF); }
    .v-edit-tag .v-avatar { box-shadow: 0 0 0 1px rgba(255, 255, 255, 0.7); }
    /* Capped at the artboard's edge like every tag, so something has to give when it
       runs out of room: the handles, which the discs beside them already carry. The verb
       and age are what the marker *is*, and they stay inside the tag's own ground —
       spilled past it they read white on the page, or not at all in light. */
    .v-edit-who { min-width: 0; overflow: hidden; text-overflow: ellipsis; }
    .v-edit-op, .v-edit-tag .v-avatar { flex: none; }

    /* ---- selection footer ---- */

    .v-selection {
      display: flex; align-items: center; gap: 0.6rem;
      padding: 0.4rem 0.75rem; font-size: 11px;
      border-top: 1px solid var(--v-line); background: var(--v-panel);
      /* A size container, so the row can shed its least essential facts when the pane
         gets narrow instead of clipping its controls (the query below). */
      container-type: inline-size;
    }
    /* Below this the fixed items alone outrun the row — measured 455px of chip, rect,
       rev, copy and steps at 11px — so the rect and the revision yield first: both live
       in the Details pane, the same reasoning that took the rect columns out of the
       outline. The path, the id, the copy button and the steps are the row's point and
       stay to the last. */
    @container (max-width: 560px) {
      .v-selection-rect, .v-selection-rev { display: none; }
    }
    /* The clip sentence is a fact only some selections carry, and a wide one — about
       160px with its gap — so with it in the row the fixed facts outgrow the 608px
       render column before the query above fires, and the path collapsed to nothing.
       A clipped selection sheds the same two facts 160px sooner, which leaves its path
       the room an unclipped one has at 560px. */
    @container (max-width: 720px) {
      .v-selection-rect:has(~ .v-clip), .v-clip ~ .v-selection-rev { display: none; }
    }
    /* Truncated from the front: the box is laid out right-to-left, so the ellipsis eats
       the *beginning* of the path and the part that names the node survives. The text
       inside is an isolate (`<bdi>`), which is what stops the RTL box reordering the
       neutral characters a real name is full of — `Home — Collection (Light)` would come
       back with its dash and its brackets in the wrong places without it. It is the only
       item here that shrinks; everything else in the footer is a fixed fact. */
    .v-selection-path {
      font-weight: 600;
      direction: rtl;
      min-width: 0; flex: 0 1 auto;
      overflow: hidden; white-space: nowrap; text-overflow: ellipsis;
    }
    .v-selection-id, .v-selection-rect, .v-selection-rev { color: var(--v-muted); }
    .v-selection-id, .v-selection-rect, .v-selection-rev, .v-clip, .v-copy { flex: none; }
    .v-selection-scale { color: var(--v-faint); }
    .v-copy {
      position: relative;
      font: 11px var(--v-mono); padding: 2px 7px; cursor: pointer;
      background: var(--v-select); color: var(--v-text);
      border: 1px solid var(--v-line); border-radius: 4px;
    }
    .v-copy.is-copied { background: var(--v-accent); border-color: var(--v-accent); color: #FFFFFF; }

    /* ---- empty state ---- */

    .v-empty { text-align: center; max-width: 34rem; }
    .v-empty-title { margin: 0 0 0.4rem; font-size: 22px; }
    .v-empty-lede { margin: 0 0 1rem; color: var(--v-muted); }
    /* The block scrolls rather than the page: a command carrying a real file path — or
       the JSON the first-frame command pipes in — is longer than the 34rem card, and a
       `pre` does not wrap. */
    .v-empty-commands {
      margin: 0; padding: 0.75rem 1rem; text-align: left;
      background: var(--v-chrome); border-radius: 6px;
      overflow-x: auto;
    }
    .v-empty-commands code { display: block; color: var(--v-muted); font-size: 12px; }
    .v-empty-commands code.is-primary { color: var(--v-text); }
    /* The block scrolls sideways with nothing at its edge to say so — a command can end
       mid-path and read as if that were the whole command. The fade is that affordance,
       and it is the *only* one: shedding and front-truncation are for rows of facts, and
       a command line has neither a least-essential fact nor a tail worth keeping.

       Always drawn, not only on overflow: CSS cannot ask whether a box overflows, and
       the alternatives (a scroll-driven animation, a resize observer) are a feature
       query and a line of script for a 2rem gradient. Over a block that fits, it tints
       the last 2rem of an empty right margin and reads as nothing. */
    .v-empty-block { position: relative; }
    .v-empty-fade {
      position: absolute; top: 0; right: 0; bottom: 0; width: 2rem;
      pointer-events: none; border-radius: 0 6px 6px 0;
      background: linear-gradient(to left, var(--v-chrome), transparent);
    }
    .v-empty .v-empty-note { margin-top: 0.8rem; color: var(--v-faint); font-size: 11px; }

    /* ==== BEGIN artboard map (B1sAM) ==================================== */

    /* The map is a page now, not a band: it fills the canvas pane, and it scrolls rather
       than shrinking past `ArtboardMap.minimumScale`, which is what a 40 000-point canvas
       needs. Its own size comes from the pane — `.v-canvas` gives it one explicit track
       each way — so the plane inside it can be any size at all without moving anything. */
    .v-map {
      display: flex;
      box-sizing: border-box;
      min-width: 0; min-height: 0;
      padding: 1.75rem;
      overflow: auto;
      background: var(--v-bg);
    }

    /* `margin: auto` rather than `justify-content: center`: a centered flex item that
       overflows its scroll container is unreachable off the left edge, an auto margin
       is not. */
    .v-map-plane {
      position: relative;
      flex: none;
      margin: auto;
      width: calc(var(--v-map-w) * var(--v-map-scale) * 1px);
      height: calc(var(--v-map-h) * var(--v-map-scale) * 1px);
    }

    /* Placed in layout points and multiplied by the one zoom, exactly as `.v-box` is
       placed over the render. The box itself does not clip: the name hangs below it, and
       `.v-map-frame` is what holds the thumbnail to the artboard's own rectangle. */
    .v-map-board {
      position: absolute;
      box-sizing: border-box;
      left: calc(var(--v-board-x) * var(--v-map-scale) * 1px);
      top: calc(var(--v-board-y) * var(--v-map-scale) * 1px);
      width: calc(var(--v-board-w) * var(--v-map-scale) * 1px);
      height: calc(var(--v-board-h) * var(--v-map-scale) * 1px);
      min-width: 3px; min-height: 3px;
      color: var(--v-muted);
      text-decoration: none;
      outline: none;
    }

    .v-map-frame {
      position: absolute; inset: 0;
      display: block; overflow: hidden;
      background: var(--v-panel);
      border: 1px solid var(--v-line);
      border-radius: 2px;
      box-shadow: var(--v-shadow);
    }
    /* A thumbnail is a real render, and the ones a warming pass has not reached arrive
       over seconds on a file with twenty artboards. An empty box reads as "this artboard
       is blank"; a shimmering one reads as "not here yet", which is the truth. It is a
       background *behind* the image, so the page is right with the script switched off —
       a loaded PNG covers it — and `viewer.js` drops the class when the image lands so
       nothing animates for the rest of the session. */
    .v-map-frame.is-loading {
      background: linear-gradient(100deg, transparent 20%, var(--v-chrome) 45%, transparent 70%) var(--v-panel);
      background-size: 300% 100%;
      animation: v-shimmer 1.4s ease-in-out infinite;
    }
    @keyframes v-shimmer {
      from { background-position: 150% 0; }
      to { background-position: -150% 0; }
    }
    /* Motion nobody asked for. The tone still separates a pending box from a blank one. */
    @media (prefers-reduced-motion: reduce) {
      .v-map-frame.is-loading { animation: none; }
    }

    /* The same color the selected state uses below, not a muted gray — that read fine
       against `--v-chrome` but disappeared against a light artboard's own render. */
    .v-map-board:hover .v-map-frame { border-color: var(--v-accent); }

    /* The thumbnail is a real render capped by `ArtboardMap.thumbnailEdge`, laid out to
       fill the box: the box is the artboard's rect scaled, and the image is that same
       rect, so the two always agree and nothing is letterboxed. */
    .v-map-thumb {
      display: block; width: 100%; height: 100%;
      object-fit: fill;
    }

    /* The one on the ring, and the one recently written to. The outline is drawn outside
       the box so it never eats a pixel of the thumbnail. */
    .v-map-board.is-focused { z-index: 3; }
    .v-map-board.is-focused .v-map-frame {
      outline: 2px solid var(--v-accent);
      outline-offset: 2px;
      border-color: var(--v-accent);
    }
    .v-map-board.is-touched .v-map-frame { border-color: var(--v-actor); }
    .v-map-board.is-focused .v-map-name { color: var(--v-text); font-weight: 700; }

    /* The label does not scale with the map: 11px at every zoom, and *under* the box
       rather than over it, so a name never covers the render it names. Its width is the
       box's, so two neighboring names cannot overlap into an unreadable run. */
    .v-map-label {
      position: absolute; top: 100%; left: 0;
      display: inline-flex; align-items: center; gap: 0.25rem;
      max-width: 100%;
      padding: 3px 1px 0;
      font: 11px var(--v-mono);
      white-space: nowrap;
      pointer-events: none;
    }
    .v-map-name { flex: 0 1 auto; min-width: 0; overflow: hidden; text-overflow: ellipsis; }

    /* On the map the mark is its glyph and the name's color — the pill's word would
       cost more width than most boxes have at a fit zoom, and the color says the same
       thing at every size. The word survives in the box's `title` and in the outline. */
    .v-map-label .v-kind-label { display: none; }
    .v-map-label .v-kind-mark { color: var(--v-mark); }
    .v-map-label:has(.v-kind-component) .v-map-name { color: var(--v-mark-component); }
    .v-map-label:has(.v-kind-instance) .v-map-name { color: var(--v-mark-instance); }
    .v-map-label:has(.v-kind-slot) .v-map-name { color: var(--v-mark-slot); }

    /* The pill's own padding (1px 5px) is shaped for the word beside the glyph; with the
       word hidden here it reads small and sits off-center. The map fixes the badge to a
       circle sized around the glyph alone and grows the glyph, so it lands dead-center on
       both axes rather than following the pill's text baseline. */
    .v-map-label .v-kind-mark { width: 15px; height: 15px; padding: 0; justify-content: center; }
    /* Flex-centering the em box does not center the *ink*: the mono font parks the shape
       ~1px above the baseline's optical middle and its side bearings lean it ~0.25px
       left (the pill's 0.02em tracking adds a trailing advance too). The translate is
       the measured correction, checked against a crosshair overlay at 16x zoom. */
    .v-map-label .v-kind-glyph { font-size: 11px; line-height: 1; letter-spacing: 0; transform: translate(0.25px, -1px); }

    /* Below the width a label can be read in — or below the height that leaves room for
       one before the next row of boxes — the name is left to the box's `title` and the
       outline. Both axes are queried, so the box is a size container. */
    @container (max-width: 24px) {
      .v-map-label { display: none; }
    }
    @container (max-height: 30px) {
      .v-map-label { display: none; }
    }

    .v-map-board { container-type: size; }

    /* ---- the map page's outline: one row per artboard ---- */

    .v-artboard-row {
      position: relative;
      padding: 3px 0.75rem;
      color: inherit; text-decoration: none;
      border-left: 3px solid transparent;
      font-size: 12px;
    }
    .v-artboard-row:hover { background: var(--v-chrome); }
    .v-artboard-row.is-focused { background: var(--v-select); }
    .v-artboard-row.is-touched { border-left-color: var(--v-actor); }

    /* The row sheds its rect before it truncates the name: the name is what a person
       navigates by, and the rect is on the map beside it and in Details. Below this the
       mark, the name and the id chip need the room — measured against a component mark,
       a twelve-character name and an instance's slashed id in the 340px pane. */
    .v-artboard-row { container-type: inline-size; }
    @container (max-width: 420px) {
      .v-artboard-row .v-outline-rect { display: none; }
    }

    /* ---- the breadcrumb's way back up ---- */

    .v-crumb-map { position: relative; display: inline-flex; align-items: center; gap: 0.3rem; }
    .v-crumb-glyph { color: var(--v-muted); font-size: 11px; }

    /* ---- stepping to the artboard either side ---- */

    .v-steps {
      display: inline-flex; align-items: center; gap: 0.35rem;
      margin-left: auto; flex: none;
    }
    .v-step {
      position: relative;
      display: inline-flex; align-items: center; justify-content: center;
      width: 18px; height: 18px; border-radius: 4px;
      font-size: 14px; line-height: 1; text-decoration: none;
      color: var(--v-muted); border: 1px solid var(--v-line);
    }
    .v-step:hover { color: var(--v-text); background: var(--v-chrome); }
    .v-step.is-end { color: var(--v-faint); border-color: transparent; }
    .v-step.is-end:hover { background: transparent; color: var(--v-faint); }
    .v-step-count { font-size: 11px; color: var(--v-faint); }

    /* ==== END artboard map (B1sAM) ====================================== */
    /* ==== BEGIN keyboard (xmGCG) ========================================== */

    /* ---- keyboard hint ---- */

    .v-key-hint {
      display: inline-flex; align-items: center; justify-content: center;
      width: 16px; height: 16px; padding: 0; border-radius: 50%;
      font: 10px var(--v-mono); font-weight: 700;
      color: var(--v-muted); background: transparent;
      border: 1px solid var(--v-line);
      cursor: pointer; flex: none;
    }
    .v-key-hint:hover { color: var(--v-text); border-color: var(--v-muted); }

    /* A real popover rather than a `title` tooltip: it opens on a click, on any device,
       and closes on Escape or a click outside without a line of script. The base rule
       hides it; the `:popover-open` rule is what shows it, and a browser that has never
       heard of popovers drops that rule and keeps the panel hidden rather than printing
       the whole table into the top bar. */
    .v-key-hint-popover {
      display: none;
      position: fixed; inset: 44px 0.9rem auto auto; margin: 0;
      max-width: 26rem; padding: 0.6rem 0.75rem;
      background: var(--v-panel); color: var(--v-text);
      border: 1px solid var(--v-line); border-radius: 8px;
      box-shadow: var(--v-shadow);
    }
    .v-key-hint-popover:popover-open { display: block; }
    .v-key-hint-popover .v-panel-title { padding: 0 0 0.4rem; }
    .v-key-list {
      display: grid; grid-template-columns: auto minmax(0, 1fr);
      gap: 0.25rem 0.75rem; margin: 0;
    }
    .v-key-keys { color: var(--v-text); font-size: 11px; white-space: nowrap; }
    .v-key-does { margin: 0; color: var(--v-muted); font-size: 11px; }

    /* ---- the way into presentation without the keyboard ---- */

    .v-present {
      display: inline-flex; align-items: center; justify-content: center;
      width: 16px; height: 16px; padding: 0; border-radius: 4px;
      font-size: 12px; line-height: 1; flex: none; cursor: pointer;
      color: var(--v-muted); background: transparent;
      border: 1px solid var(--v-line);
    }
    .v-present:hover { color: var(--v-text); border-color: var(--v-muted); }

    /* ---- outline disclosure and collapse ---- */

    /* The wrapper is sized to match the SVG glyph it holds (`.v-disclosure-glyph`, above)
       so a leaf's blank spacer reserves the same width and every row's name still lines
       up in one column, whether or not that row has a triangle to show. */
    .v-outline-row[hidden] { display: none; }
    .v-disclose {
      display: inline-flex; align-items: center; justify-content: center;
      width: 18px; height: 18px; flex: none;
      transition: transform 0.15s ease;
    }
    .v-outline-row.is-row-collapsed .v-disclose { transform: rotate(-90deg); }

    /* ---- presentation mode: the artboard on its background, and nothing else ---- */

    /* The canvas leaves the grid entirely rather than being handed a bigger track in it.
       Hiding the chrome used to leave `.v-main` sizing itself from its contents, and
       every pane below it sizes its row with `minmax(0, 1fr)` — a track whose *minimum*
       is zero, so with no definite height coming down it resolves to nothing and the
       render measured itself against a pane 0 px tall. `fitStage()` then clamped at its
       0.05 floor and drew a 400-point artboard 20 px wide. Fixed to the viewport, the
       pane is the screen by construction and there is no chain to collapse. */
    body.is-presenting.v-body { grid-template-rows: minmax(0, 1fr); }
    body.is-presenting .v-topbar,
    body.is-presenting .v-side,
    body.is-presenting .v-grip,
    body.is-presenting .v-selection,
    body.is-presenting #v-overlay {
      display: none;
    }
    body.is-presenting .v-canvas {
      position: fixed; inset: 0; z-index: 40;
      background: var(--v-bg);
    }
    body.is-presenting .v-canvas-body,
    body.is-presenting .v-render-region {
      grid-template-rows: minmax(0, 1fr);
    }
    body.is-presenting .v-stage { box-shadow: none; }

    /* The way out, said once on the way in: shown at full opacity while the script holds
       `is-flashing`, then transitioned away when it lets go. */
    /* The pill is styled on its own and only *shown* by the mode, so a surface that
       cannot enter the mode — a preview frame — can draw it by lifting `display`. */
    .v-present-hint {
      display: none;
      position: fixed; z-index: 50;
      left: 50%; bottom: 2rem; transform: translateX(-50%);
      padding: 0.4rem 0.9rem; border-radius: 999px;
      font: 11px var(--v-mono); color: var(--v-text);
      background: var(--v-chrome); border: 1px solid var(--v-line);
      box-shadow: var(--v-shadow);
      pointer-events: none;
      opacity: 0; transition: opacity 0.6s ease-out;
    }
    body.is-presenting .v-present-hint { display: block; }
    body.is-presenting .v-present-hint.is-flashing { opacity: 1; transition: none; }

    /* ==== END keyboard (xmGCG) ============================================ */
    /* ==== BEGIN follow + unread (MehU9) ==== */

    .v-follow { display: inline-flex; align-items: center; gap: 0.4rem; }
    .v-follow-form { display: inline-flex; align-items: center; gap: 0.3rem; margin: 0; }
    .v-follow-label { font-size: 11px; color: var(--v-muted); font-family: var(--v-mono); }
    .v-follow-select {
      font: 11px var(--v-mono); color: var(--v-text);
      background: var(--v-panel); border: 1px solid var(--v-line);
      border-radius: 4px; padding: 2px 4px;
    }
    .v-follow-resume {
      font: 11px var(--v-mono); color: var(--v-accent-ink); text-decoration: none;
      padding: 2px 6px; border-radius: 4px; border: 1px solid var(--v-accent);
      white-space: nowrap;
    }
    .v-follow-resume:hover { background: var(--v-select); }

    /* The unread dot hangs on the attribute, not on a class: the map and the artboard
       listing are fragments, so the marks are re-applied by the script after every swap,
       and any other view of the artboards inherits them by carrying the same attribute.
       The map's boxes are already `position: absolute`, which is what the dot needs; a
       `position: relative` here would override that and un-place every box, so each of
       the other carriers positions itself in its own rule instead.

       The breadcrumb's map crumb carries the same dot for the whole file: on an artboard
       page there are no boxes to mark, and "something changed somewhere else" is exactly
       what the way back up should say. */
    [data-artboard][data-unread="1"]::after,
    .v-crumb-map[data-unread="1"]::after {
      content: ""; position: absolute; top: 3px; right: 3px;
      width: 6px; height: 6px; border-radius: 50%;
      background: var(--v-warn); box-shadow: 0 0 0 2px var(--v-panel);
    }
    .v-crumb-map[data-unread="1"] { padding-right: 10px; }
    .v-crumb-map[data-unread="1"]::after { top: 0; right: 0; box-shadow: 0 0 0 2px var(--v-chrome); }

    /* ==== END follow + unread (MehU9) ==== */

    /* ==== BEGIN right pane + resize (k92mT) ============================ */

    /* Every pane is a grid track whose size is a custom property, so dragging a
       handle is one property write and the browser lays the rest out. The
       fallbacks in each var() are the sizes the page had before it was
       resizable, which is what a browser with no stored sizes — or no script —
       still gets. */

    :root { --v-grip: 6px; }

    .v-layout-artboard .v-main {
      grid-template-columns:
        var(--v-col-left, 340px) var(--v-grip)
        minmax(0, 1fr)
        var(--v-grip) var(--v-col-right, 320px);
      gap: 0;
    }

    .v-grip { background: var(--v-line); border: 0; padding: 0; }
    .v-grip[data-axis="x"] { cursor: col-resize; }
    .v-grip[data-axis="y"] { cursor: row-resize; }
    .v-grip:hover, .v-grip.is-dragging { background: var(--v-accent); }

    /* The left column is two stacked panels with a seam between them. */
    .v-side-left {
      display: grid;
      grid-template-rows: minmax(0, 1fr) var(--v-grip) var(--v-row-lower, 240px);
      overflow: hidden;
    }
    .v-side-left .v-outline { min-height: 0; overflow-y: auto; }
    .v-side-left .v-variables { min-height: 0; overflow-y: auto; }
    .v-side-left .v-variables.is-collapsed { overflow: hidden; }

    /* ---- the canvas ---- */

    .v-canvas-body {
      display: grid; grid-template-columns: minmax(0, 1fr);
      min-height: 0; overflow: hidden;
    }

    /* ---- the code tab's pane ---- */

    /* A header that stays put over a body that scrolls — the same two-row shape it
       had as half the canvas, now sized by the right pane's column. The code line
       wraps rather than scrolling sideways: a pane this narrow would otherwise hide
       the end of every line behind a horizontal scrollbar. */
    .v-code {
      display: grid; grid-template-rows: auto minmax(0, 1fr);
      min-height: 0; min-width: 0; overflow: hidden; background: var(--v-panel);
    }
    .v-code-head {
      display: flex; align-items: center; gap: 0.5rem; flex-wrap: wrap;
      padding: 0.4rem 0.6rem; border-bottom: 1px solid var(--v-line);
    }
    .v-code-form { display: flex; align-items: center; gap: 0.35rem; }
    .v-code-path { color: var(--v-muted); font-size: 11px; margin-left: auto; }
    .v-code-body {
      margin: 0; padding: 0.6rem 0.75rem; overflow: auto; min-height: 0;
      font: 11px/1.55 var(--v-mono); white-space: pre-wrap; word-break: break-word;
      tab-size: 2;
    }
    .v-code .v-empty-note { padding: 0.6rem 0.75rem; }

    /* ---- the right pane's tabs ---- */

    .v-side-right {
      display: grid; grid-template-rows: auto minmax(0, 1fr); overflow: hidden;
    }
    .v-tabbar {
      display: flex; gap: 0.25rem; padding: 0.5rem 0.75rem 0.4rem;
      border-bottom: 1px solid var(--v-line);
    }
    .v-tab {
      font: 11px var(--v-mono); padding: 3px 9px; border-radius: 999px;
      color: var(--v-muted); text-decoration: none; border: 1px solid transparent;
    }
    .v-tab:hover { color: var(--v-text); }
    .v-tab.is-current {
      color: var(--v-text); border-color: var(--v-line); background: var(--v-chrome);
    }

    /* Every panel is rendered; the tab decides which one is shown, so a fragment
       can land in one nobody is looking at and switching is instant. Code is a
       grid rather than a block: its header pins while its body scrolls. */
    .v-pane { display: none; min-height: 0; overflow-y: auto; }
    .v-side-right[data-tab="activity"] .v-pane[data-pane="activity"],
    .v-side-right[data-tab="details"] .v-pane[data-pane="details"],
    .v-side-right[data-tab="export"] .v-pane[data-pane="export"] { display: block; }
    .v-side-right[data-tab="code"] .v-pane[data-pane="code"] {
      display: grid; overflow: hidden;
    }

    /* ---- details ---- */

    .v-detail-head {
      display: flex; flex-wrap: wrap; align-items: center; gap: 0.4rem;
      padding: 0.5rem 0.75rem; border-bottom: 1px solid var(--v-line);
    }
    .v-detail-name { font-weight: 600; }
    .v-detail-path { color: var(--v-muted); font-size: 11px; }
    .v-detail-instance {
      font: 10px var(--v-mono); color: var(--v-mark-instance);
      border: 1px solid currentColor; border-radius: 999px; padding: 0 5px;
    }

    .v-detail-row {
      display: grid; grid-template-columns: 8.5rem minmax(0, 1fr) auto;
      gap: 0.2rem 0.5rem; align-items: baseline;
      padding: 0.3rem 0.75rem; border-top: 1px solid var(--v-line);
    }
    .v-detail-rows .v-detail-row:first-child { border-top: 0; }
    .v-detail-row:hover { background: var(--v-chrome); }
    .v-detail-key {
      font-size: 11px; color: var(--v-muted);
      overflow: hidden; text-overflow: ellipsis;
    }
    .v-detail-value { overflow: hidden; text-overflow: ellipsis; white-space: nowrap; }
    .v-detail-origin {
      font: 10px var(--v-mono); padding: 0 5px; border-radius: 999px;
      border: 1px solid var(--v-line); color: var(--v-faint); white-space: nowrap;
    }
    .v-detail-origin[data-origin="variable"] {
      color: var(--v-mark-component); border-color: currentColor;
    }
    .v-detail-origin[data-origin="override"] {
      color: var(--v-mark-instance); border-color: currentColor;
    }
    .v-detail-source {
      grid-column: 1 / -1; font-size: 10px; color: var(--v-faint);
      overflow: hidden; text-overflow: ellipsis;
    }

    /* ---- export ---- */

    .v-export-form { display: grid; gap: 0.5rem; padding: 0.6rem 0.75rem; }
    .v-export-field {
      display: flex; align-items: center; justify-content: space-between; gap: 0.5rem;
    }
    .v-export-label { color: var(--v-muted); font-size: 11px; }
    /* One width for all three, so they read as one column of a form: a `min-width`
       let the number field take the browser's default size and jut 37px further left
       than the two selects above it. */
    .v-export-form select,
    .v-export-form input {
      font: 12px var(--v-sans); padding: 2px 5px;
      width: 8rem; box-sizing: border-box;
      background: var(--v-panel); color: var(--v-text);
      border: 1px solid var(--v-line); border-radius: 4px;
    }
    .v-export-go {
      justify-self: start; font: 11px var(--v-mono); padding: 4px 12px;
      cursor: pointer; background: var(--v-select); color: var(--v-text);
      border: 1px solid var(--v-line); border-radius: 4px;
    }
    .v-export .v-empty-note { padding: 0 0.75rem 0.75rem; }

    /* ==== END right pane + resize (k92mT) ============================== */
    """
}
