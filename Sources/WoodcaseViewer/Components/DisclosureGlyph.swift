//
//  DisclosureGlyph.swift
//  WoodcaseViewer
//

import Elementary
import Foundation

/// A small triangular disclosure control, for any expand/collapse toggle in the viewer.
///
/// Drawn as inline SVG rather than the bare `▾` character it replaces: a text glyph
/// renders at a different weight and baseline in every system font, so a `<button>`'s
/// triangle and a `<summary>`'s never quite lined up. This is one shape, sized the same
/// everywhere it appears, wrapped in a box wide enough to give it a comfortable click
/// target — the visible triangle is a few pixels across, but the box around it is not.
///
/// The shape always points down — the *open* orientation — so a caller that starts
/// expanded (the Variables pane's own header) needs no rotation at all, while one that
/// starts collapsed (a variable row's `<summary>`) rotates it in CSS by selecting on its
/// own open state. See the shared `.v-disclosure-glyph` rule in ``ViewerStylesheet``.
///
/// Carries no styling of its own beyond that shared rule — no panel-specific class, no
/// inline color — so any pane can reuse it unchanged; the Outline pane is next.
public struct DisclosureGlyph: HTML {
    /// Creates a glyph.
    public init() {}

    public var body: some HTML {
        span(.class("v-disclosure-glyph"), .custom(name: "aria-hidden", value: "true")) {
            SVG.svg(.viewBox(0, 0, 10, 10)) {
                SVG.polygon(.points("1,3 9,3 5,8"), .fill("currentColor"))
            }
        }
    }
}
