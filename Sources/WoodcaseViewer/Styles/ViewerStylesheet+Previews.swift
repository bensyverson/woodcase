//
//  ViewerStylesheet+Previews.swift
//  WoodcaseViewer
//

import Foundation

/// The rules the `/preview` pages add to the viewer's own: the index's list, the
/// canvas's captions, and — the part that matters — one rule per ``PreviewFrame``.
///
/// ## The frames are production geometry, not new numbers
///
/// A component alone on a blank page is the wrong picture, so a preview state is shown
/// inside the surface it declares, at the width that surface really has. Every width
/// below is therefore the *same custom property* the artboard layout's grid uses
/// (`--v-col-left`, `--v-col-right`, `--v-grip`), with the same fallback: drag the
/// outline column wider in production and these move with it, because there is one
/// number and not two.
///
/// The one number of its own is `--v-preview-window`, the reference window the render
/// column is measured against — the canvas is `1fr` in production, which is only a
/// width once a window has a size, and the review loop's is
/// `sleepy shot … --size 1280x800`.
public extension ViewerStylesheet {
    /// The preview pages' rules, appended to ``ViewerStylesheet/core``.
    static let previewRules = """

    /* ==== BEGIN preview pages (EGno2F) ================================= */

    /* The reference window the render column is measured against: the size the review
       loop shoots at. Every other frame width is the production custom property. */
    :root { --v-preview-window: 1280px; }

    .v-layout-preview .v-main { overflow-y: auto; padding: 1.6rem 2rem; }
    .v-preview-index, .v-preview-canvas { max-width: var(--v-preview-window); margin: 0 auto; }

    /* ---- the index ---- */

    .v-preview-list {
      list-style: none; margin: 1.2rem 0 0; padding: 0;
      display: grid; gap: 1px; background: var(--v-line);
      border: 1px solid var(--v-line); border-radius: 8px; overflow: hidden;
    }
    .v-preview-entry {
      display: grid; grid-template-columns: minmax(0, 1fr) auto;
      gap: 0.15rem 1rem; padding: 0.7rem 0.9rem; background: var(--v-panel);
    }
    .v-preview-entry-link { font-weight: 600; color: var(--v-text); text-decoration: none; }
    .v-preview-entry-link:hover { color: var(--v-accent); }
    .v-preview-count { font-size: 11px; color: var(--v-muted); justify-self: end; }
    .v-preview-blurb { grid-column: 1 / -1; margin: 0; color: var(--v-muted); }
    .v-preview-source {
      grid-column: 1 / -1; font-size: 11px; color: var(--v-faint);
      overflow: hidden; text-overflow: ellipsis;
    }

    /* ---- one state on the canvas ---- */

    .v-preview-state { margin: 2rem 0 0; }
    .v-preview-state-name { margin: 0; font-size: 13px; font-weight: 600; }
    .v-preview-anchor {
      font-family: var(--v-mono); color: var(--v-faint);
      text-decoration: none; margin-right: 0.4rem;
    }
    .v-preview-anchor:hover { color: var(--v-accent); }
    .v-preview-note { margin: 0.2rem 0 0; color: var(--v-muted); max-width: 46rem; }
    /* A block, not inline: a strip frame is an inline box at its natural size, and
       inline it flowed onto the permalink's line and covered its last characters. The
       drawing sits on its own line under the address, with the same gap the note has. */
    .v-preview-permalink {
      display: block; margin: 0.3rem 0 0.6rem; width: fit-content;
      font-size: 11px; color: var(--v-faint); text-decoration: none;
    }
    .v-preview-permalink:hover { color: var(--v-accent); }
    .v-preview-whole { margin: 0.3rem 0 0; color: var(--v-faint); }

    /* ---- the frames ---- */

    .v-preview-frame { border: 1px solid var(--v-line); border-radius: 6px; overflow: hidden; }

    /* An atom at its natural size, on one line, over the chrome it usually sits on —
       the presence stack's avatar rings are drawn in chrome and read as holes on
       anything else. */
    .v-preview-frame[data-frame="strip"] {
      display: inline-flex; align-items: center; gap: 0.5rem;
      padding: 0.5rem 0.7rem; background: var(--v-chrome);
    }

    /* The two panes are the artboard grid's own tracks, fallbacks and all. */
    .v-preview-frame[data-frame="left-pane"] { width: var(--v-col-left, 340px); background: var(--v-panel); }
    .v-preview-frame[data-frame="right-pane"] { width: var(--v-col-right, 320px); background: var(--v-panel); }

    /* The render column is what the reference window has left after the two panes and
       their grips — the same subtraction the `1fr` track performs. */
    .v-preview-frame[data-frame="canvas"] {
      width: calc(
        var(--v-preview-window) - var(--v-col-left, 340px)
        - var(--v-col-right, 320px) - 2 * var(--v-grip)
      );
      max-width: 100%;
      background: var(--v-bg);
    }

    /* The dashboard's body: full width, and the same gutters .v-layout-dashboard gives
       its main, because that padding is part of how a card grid is read. */
    .v-preview-frame[data-frame="body"] { width: 100%; padding: 1.6rem 2rem; background: var(--v-bg); }

    /* The chrome strip spans the window, on the chrome it is: the whole bar paints its own
       ground, but a bare control from it — a picker, the keyboard hint — does not, and on
       the page's paper it is a different picture from the one production shows. A bare
       control also gets the bar's own inset rather than hugging the frame's border. */
    .v-preview-frame[data-frame="top-bar"] { width: 100%; background: var(--v-chrome); }
    .v-preview-frame[data-frame="top-bar"]:not(:has(> .v-topbar)) { padding: 0.55rem 0.9rem; }

    /* Two overlays a frame cannot open: the keyboard hint's popover (open only once
       `showPopover` has run) and the presentation hint (shown only in the mode). A
       picture of them closed is a picture of nothing, so a frame that holds one draws it
       in place, at rest and fully opaque — the same markup, with its placement lifted. */
    .v-preview-frame > .v-key-hint-popover,
    .v-preview-frame > .v-present-hint {
      display: block; position: static; inset: auto; transform: none;
      width: fit-content; opacity: 1; transition: none;
    }
    .v-preview-frame > .v-key-hint-popover { margin: 0.5rem 0 0; }
    .v-preview-frame > .v-present-hint { margin: 2rem auto; }

    /* A code span in a caption is a command or a name an agent would paste: the mono the
       rest of the page gives those, at the size it gives every mono fact. */
    .v-preview-note code, .v-section-subtitle code, .v-preview-blurb code { font-size: 11px; }

    /* `page` has no rule on purpose: a whole page is served as its own document. */

    /* ==== END preview pages (EGno2F) =================================== */
    """
}
