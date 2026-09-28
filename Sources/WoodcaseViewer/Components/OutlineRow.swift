//
//  OutlineRow.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// One node in the outline panel: disclosure control, glyph, name, clip flag, id.
///
/// The row is an `<a href="?node=…">`, not a button. Selection is view state and view
/// state lives in the query, so the row works with the script off, the URL describes
/// what you are looking at, and back and forward do the obvious thing. The script
/// intercepts the click to swap fragments instead of navigating; that is an
/// optimisation, not the mechanism.
///
/// A row touched inside the last 30 seconds carries its editors' colour as a bar down
/// its left edge — the only other place, with the render's edit markers, an identity
/// colour is allowed.
///
/// The row carries no x/y or w/h: a node's settled rect belongs to the Details pane,
/// which shows it beside every other property, not the outline, which is a listing of
/// what a file contains rather than where each thing sits. ``ArtboardRow`` keeps a rect
/// column — it lists artboards on a map, and a map is exactly where position matters.
public struct OutlineRow: HTML {
    /// Creates a row.
    ///
    /// - Parameters:
    ///   - row: The settled tree row to draw.
    ///   - file: The file's id, for the link.
    ///   - artboard: The artboard on screen, which the link selects *into*. `/files/{id}`
    ///     is the map now, so a row that linked there would navigate out of the artboard
    ///     it was clicked in — and the script, which only rewrites the query, would
    ///     disagree with its own `href`.
    ///   - state: The current view state, which the link carries forward.
    ///   - editors: Identities that touched this node inside the recency window, in the
    ///     order the log first saw them.
    public init(
        row: TreeRow,
        file: String,
        artboard: String,
        state: ViewState,
        editors: [String] = []
    ) {
        self.row = row
        self.file = file
        self.artboard = artboard
        self.state = state
        self.editors = editors
    }

    /// The settled tree row to draw.
    public let row: TreeRow

    /// The file's id.
    public let file: String

    /// The artboard the row selects into.
    public let artboard: String

    /// The current view state.
    public let state: ViewState

    /// Identities that touched this node inside the recency window.
    public let editors: [String]

    /// Whether this row is the selected one.
    ///
    /// Both spellings count: a link the page wrote carries the id, and a URL a person
    /// typed is far more likely to carry the name path.
    public var isSelected: Bool {
        state.node == row.id || state.node == row.address
    }

    /// What a person calls this node: its name, or its id marker when it has none.
    public var label: String {
        row.name ?? "#\(row.id)"
    }

    /// The colour of the bar down a touched row's left edge.
    ///
    /// The first editor's, because ``editors`` is in the log's order of first
    /// appearance: when two agents touch one node the bar keeps the colour it had
    /// rather than flickering between them, and the full list is on `data-editors`.
    var editorColor: String {
        ActorColor(name: editors.first ?? "").css
    }

    /// The glyph a node type is drawn with.
    ///
    /// A single character rather than an icon font: the outline is a dense text table
    /// and a glyph column that a person can also select and paste is worth more here
    /// than a prettier mark.
    public enum Glyph: String, Friendly {
        /// A frame — the container everything else sits in.
        case frame = "⊟"
        /// A group — a box with no paint of its own.
        case group = "⊞"
        /// Text.
        case text = "T"
        /// An icon.
        case icon = "✦"
        /// A component instance.
        case instance = "◇"
        /// A component definition.
        case component = "◈"
        /// A shape — rectangle, ellipse, path, line, polygon.
        case shape = "▢"
        /// Anything else, including a type this build does not know.
        case other = "·"

        /// The glyph for a tree row.
        ///
        /// - Parameter row: The row to draw.
        /// - Returns: Its glyph.
        public static func of(_ row: TreeRow) -> Glyph {
            if row.isReusable { return .component }
            if row.isInstance { return .instance }
            return switch row.type {
            case "frame": .frame
            case "group": .group
            case "text": .text
            case "icon": .icon
            case "rectangle", "ellipse", "path", "line", "polygon": .shape
            default: .other
            }
        }
    }

    /// The settled rect, as the tree verb spells it: `x,y w×h`.
    ///
    /// Shared with ``ArtboardRow``, the only row that still shows one — a row here no
    /// longer does, but the format the CLI's `tree` verb prints stays one formatter.
    ///
    /// - Parameter rect: The rect, or `nil` when the layout engine produced none.
    /// - Returns: The text, or an em dash when there is no rect — never a zero rect
    ///   standing in for an unknown one.
    static func rectText(_ rect: PenRect?) -> String {
        guard let rect else { return "—" }
        return "\(number(rect.x)),\(number(rect.y)) \(number(rect.width))×\(number(rect.height))"
    }

    /// A layout number with no trailing `.0`.
    static func number(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15
            ? String(Int(value.rounded()))
            : String(format: "%.1f", value)
    }

    /// The definition, instance or slot mark for this row, when it carries one.
    ///
    /// Its own glyph replaces the plain type glyph rather than sitting beside it: a
    /// component or instance row already told you what role it plays, and a bare "◇"
    /// repeated next to a labelled "◇ instance" badge is noise, not information.
    var mark: KindMark {
        KindMark(isReusable: row.isReusable, isInstance: row.isInstance, isSlot: row.isSlot)
    }

    /// Whether the render draws a child inside this row's box, and so whether the row
    /// gets a working disclosure control rather than a blank spacer.
    ///
    /// Read straight off the row rather than by looking at neighbouring rows in the
    /// list: the outline is always rendered fully expanded (a collapsed row is
    /// client-only state, applied after the fact), so a row's own ``TreeRow/childCount``
    /// already answers it without walking anything.
    var hasChildren: Bool {
        row.childCount > 0
    }

    public var body: some HTML {
        a(
            .href(ViewerLink.artboard(
                file: file,
                artboard: artboard,
                state: state.selecting(isSelected ? nil : row.id)
            )),
            .class("v-row v-outline-row"),
            .data("node", value: row.id),
            .data("address", value: row.address),
            .style("--v-depth: \(row.depth)")
        ) {
            span(.class(hasChildren ? "v-disclose has-children" : "v-disclose")) {
                if hasChildren { DisclosureGlyph() }
            }
            if mark.kind == nil {
                span(.class("v-glyph")) { Glyph.of(row).rawValue }
            }
            mark
            span(.class("v-outline-name")) { label }
                .attributes(.class("is-unnamed"), when: row.name == nil)
            if row.clip != .none {
                span(.class("v-clip"), .title("This node is \(row.clip.rawValue)ly outside its parent.")) { "⚠" }
            }
            if row.childCount > 0, row.isInstance {
                span(.class("v-outline-children")) { "+\(row.childCount)" }
            }
            IdChip(id: row.id, extraClasses: "v-outline-id")
        }
        .attributes(.class("is-selected"), when: isSelected)
        .attributes(.class("is-clipped"), when: row.clip != .none)
        .attributes(
            .class("is-touched"),
            .style("--v-actor: \(editorColor)"),
            .data("editors", value: editors.joined(separator: " ")),
            when: !editors.isEmpty
        )
    }
}
