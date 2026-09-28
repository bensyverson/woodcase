//
//  SelectionBar.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The footer under the render: what you have selected, spelled the way a command line
/// wants it.
///
/// This is the page's actual product. Everything above it helps you find the node; this
/// line is the string you paste into `woodcase set` — the name path, the id, the settled
/// rect, and a copy affordance so it survives the trip.
///
/// It also carries ``ArtboardSteps`` at its far end. With the bird's-eye map moved out of
/// the canvas into a page of its own, this is the one line that is always about *this
/// artboard*, so `‹ 2 of 5 ›` belongs here rather than in a strip that no longer exists.
public struct SelectionBar: HTML {
    /// Creates a bar.
    ///
    /// - Parameters:
    ///   - file: The file's id, for the step links.
    ///   - artboard: The artboard being shown.
    ///   - artboards: Every artboard of the file, in document order, for the steps.
    ///   - scale: Pixels per layout point the render was made at.
    ///   - revision: The document revision the page was read at.
    ///   - selection: The selected node, or `nil` when nothing is selected.
    ///   - state: The current view state, which the step links carry forward.
    public init(
        file: String,
        artboard: Artboard,
        artboards: [Artboard] = [],
        scale: Double,
        revision: String,
        selection: ArtboardLayout.Node?,
        state: ViewState = ViewState()
    ) {
        self.file = file
        self.artboard = artboard
        self.artboards = artboards
        self.scale = scale
        self.revision = revision
        self.selection = selection
        self.state = state
    }

    /// The file's id.
    public let file: String

    /// The artboard being shown.
    public let artboard: Artboard

    /// Every artboard of the file, in document order.
    public let artboards: [Artboard]

    /// The current view state.
    public let state: ViewState

    /// Device pixels per layout point the PNG was rendered at — its density, not the
    /// size it is drawn at. The footer reports it because it is what tells you whether a
    /// blurry-looking render is the render or the display.
    public let scale: Double

    /// The document revision the page was read at.
    public let revision: String

    /// The selected node, or `nil` when nothing is selected.
    public let selection: ArtboardLayout.Node?

    /// How much of the selected node falls outside its parent.
    var clip: TreeRow.Clip {
        selection?.clip ?? .none
    }

    /// The rect of the selection, as the tree verb spells it.
    var rectText: String {
        guard let selection else { return "" }
        return OutlineRow.rectText(
            PenRect(x: selection.x, y: selection.y, width: selection.width, height: selection.height)
        )
    }

    public var body: some HTML {
        footer(.class("v-selection"), .id("v-selection")) {
            if let selection {
                // The path is truncated from its *front* — `…/Fav Card 2/Cover Image`
                // rather than `Home — Collection (Light)/Con…` — because the end of a
                // path is the part that names the node. The stylesheet does it by
                // laying the box out right-to-left; the `<bdi>` is what keeps the text
                // itself the way round it was written, since an em dash, a slash and a
                // parenthesis are all *neutral* characters that an RTL box would
                // otherwise reorder and mirror.
                span(.class("v-mono v-selection-path"), .id("v-selection-path")) {
                    bdi { selection.path }
                }
                IdChip(id: selection.id, extraClasses: "v-mono v-selection-id")
                span(.class("v-mono v-selection-rect")) { rectText }
                if clip != .none {
                    span(.class("v-clip")) { "⚠ \(clip.rawValue)ly outside its parent" }
                }
                span(.class("v-mono v-selection-rev")) { "rev \(OutlinePanel.shortRevision(revision))" }
                button(
                    .class("v-copy"),
                    .type(.button),
                    .data("copy", value: selection.path)
                ) {
                    // Both words, as on the id chip: the script flips `is-copied` and the
                    // stylesheet shows `copied` over the label, which keeps the width.
                    span(.class("v-copy-label")) { "copy address" }
                    span(.class("v-copied"), .custom(name: "aria-hidden", value: "true")) { "copied" }
                }
            } else {
                span(.class("v-selection-scale")) {
                    "\(artboard.name ?? artboard.id) · "
                        + "\(OutlineRow.number(artboard.width))×\(OutlineRow.number(artboard.height)) pt · "
                        + "rendered \(OutlineRow.number(scale))×"
                }
            }
            ArtboardSteps(
                file: file, artboards: artboards, current: artboard.id, state: state
            )
        }
    }
}
