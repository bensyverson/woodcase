//
//  ArtboardOutline.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The left panel while the map is showing: one row per artboard, in document order.
///
/// The map answers *where* an artboard sits; a list answers *what there is* — the two
/// readings of a file you want side by side when you do not yet know it. So the node
/// outline steps aside for an artboard listing while the map is on screen, and comes back
/// the moment you drill in.
///
/// It takes the outline's own element id, `v-outline`, rather than sitting beside it: the
/// two never both exist, they occupy the same slot in the same pane, and one swap target
/// means the script needs no idea which of them it is refreshing.
///
/// Also the fragment served at `GET /files/{file}/artboards`.
public struct ArtboardOutline: HTML {
    /// Creates a panel.
    ///
    /// - Parameters:
    ///   - artboards: Every artboard of the file, in document order.
    ///   - revision: The document revision they were read at.
    ///   - file: The file's id.
    ///   - state: The current view state.
    ///   - editors: For each artboard id, the identities that touched something inside it
    ///     inside the recency window.
    public init(
        artboards: [Artboard],
        revision: String,
        file: String,
        state: ViewState,
        editors: [String: [String]] = [:]
    ) {
        self.artboards = artboards
        self.revision = revision
        self.file = file
        self.state = state
        self.editors = editors
    }

    /// Every artboard of the file, in document order.
    public let artboards: [Artboard]

    /// The document revision they were read at.
    public let revision: String

    /// The file's id.
    public let file: String

    /// The current view state.
    public let state: ViewState

    /// For each artboard id, the identities that touched something inside it recently.
    public let editors: [String: [String]]

    public var body: some HTML {
        section(.class("v-panel v-outline v-artboards"), .id(ViewerLink.Fragment.artboards.target)) {
            header(.class("v-panel-head")) {
                h2(.class("v-panel-title")) { "Artboards" }
                span(.class("v-panel-note"), .title(revision)) { "rev \(OutlinePanel.shortRevision(revision))" }
            }
            if artboards.isEmpty {
                p(.class("v-empty-note")) { "This file has no top-level frames to draw." }
            } else {
                div(.class("v-outline-rows")) {
                    for artboard in artboards {
                        ArtboardRow(
                            artboard: artboard,
                            file: file,
                            state: state,
                            editors: editors[artboard.id] ?? []
                        )
                    }
                }
            }
        }
    }
}
