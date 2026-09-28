//
//  ArtboardRow.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// One artboard in the map page's outline: glyph or kind mark, name, settled rect, id.
///
/// Deliberately the same shape as an ``OutlineRow`` — the same columns in the same order,
/// the same ``KindMark``, the same click-to-copy ``IdChip`` — because it stands in the
/// same place and answers the same question one level up. What differs is where it goes:
/// a node row selects a node inside the artboard you are on, this one *drills into* an
/// artboard, with exactly the link its box on the map carries.
///
/// It carries `data-artboard`, so the unread dot, the keyboard's focus ring and the
/// follow-drop handler all reach it without knowing this component exists.
public struct ArtboardRow: HTML {
    /// Creates a row.
    ///
    /// - Parameters:
    ///   - artboard: The artboard to list.
    ///   - file: The file's id, for the link.
    ///   - state: The current view state, which the link carries forward.
    ///   - editors: Identities that touched something inside this artboard inside the
    ///     recency window, in the order the log first saw them.
    ///   - unread: Whether this artboard changed since this browser last looked at it.
    ///     Always `false` on the server — see ``unread``.
    public init(
        artboard: Artboard,
        file: String,
        state: ViewState,
        editors: [String] = [],
        unread: Bool = false
    ) {
        self.artboard = artboard
        self.file = file
        self.state = state
        self.editors = editors
        self.unread = unread
    }

    /// The artboard to list.
    public let artboard: Artboard

    /// The file's id.
    public let file: String

    /// The current view state.
    public let state: ViewState

    /// Identities that touched something inside this artboard recently.
    public let editors: [String]

    /// Whether the row wears the unread dot.
    ///
    /// The server always renders `false`: what this browser has already seen lives in
    /// its own `localStorage`, and ``ViewerScript`` sets `data-unread="1"` on every
    /// element carrying this artboard's id once it knows. It is a parameter so the
    /// state can be *declared* — a preview sets exactly the attribute the script sets,
    /// and the stylesheet rule (`[data-artboard][data-unread="1"]::after`) is the real
    /// one.
    public let unread: Bool

    /// What a person calls this artboard: its name, or its id marker when it has none.
    public var label: String {
        artboard.name ?? "#\(artboard.id)"
    }

    /// The definition, instance or slot mark for this artboard, when it carries one.
    var mark: KindMark {
        KindMark(
            isReusable: artboard.isReusable,
            isInstance: artboard.isInstance,
            isSlot: artboard.isSlot
        )
    }

    /// The colour of the bar down a touched row's left edge — the first editor's, as an
    /// outline row does it, so two agents on one artboard do not make it flicker.
    var editorColor: String {
        ActorColor(name: editors.first ?? "").css
    }

    /// The artboard's rect on the canvas, spelled as the tree verb spells a node's.
    var rectText: String {
        OutlineRow.rectText(PenRect(
            x: artboard.x, y: artboard.y, width: artboard.width, height: artboard.height
        ))
    }

    public var body: some HTML {
        a(
            .href(ViewerLink.artboard(file: file, artboard: artboard.id, state: state.selecting(nil))),
            .class("v-row v-artboard-row"),
            .data("artboard", value: artboard.id)
        ) {
            if mark.kind == nil {
                span(.class("v-glyph")) { OutlineRow.Glyph.frame.rawValue }
            }
            mark
            span(.class("v-outline-name")) { label }
                .attributes(.class("is-unnamed"), when: artboard.name == nil)
            span(.class("v-outline-rect")) { rectText }
            IdChip(id: artboard.id, extraClasses: "v-outline-id")
        }
        .attributes(
            .class("is-touched"),
            .style("--v-actor: \(editorColor)"),
            .data("editors", value: editors.joined(separator: " ")),
            when: !editors.isEmpty
        )
        .attributes(.data("unread", value: "1"), when: unread)
    }
}
