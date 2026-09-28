//
//  OutlinePanel.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The left panel: the settled tree, one ``OutlineRow`` per node.
///
/// The rows are the tree verb's rows — the same ``TreeRow`` values `woodcase tree
/// --json` prints — so what an agent reads on the command line and what a person clicks
/// in the browser are one model with two formatters, and neither can drift.
///
/// This is also the fragment served at `GET /files/{file}/outline`, which is what the
/// script swaps in when a change arrives: a live update is a server render, never a
/// second implementation in JavaScript.
public struct OutlinePanel: HTML {
    /// Creates a panel.
    ///
    /// - Parameters:
    ///   - rows: The settled tree rows, in document order.
    ///   - revision: The document revision the rows were read at.
    ///   - file: The file's id.
    ///   - artboard: The artboard on screen, which every row selects into.
    ///   - state: The current view state.
    ///   - editors: For each node id, the identities that touched it inside the recency
    ///     window, in the log's order of first appearance.
    public init(
        rows: [TreeRow],
        revision: String,
        file: String,
        artboard: String,
        state: ViewState,
        editors: [String: [String]] = [:]
    ) {
        self.rows = rows
        self.revision = revision
        self.file = file
        self.artboard = artboard
        self.state = state
        self.editors = editors
    }

    /// The artboard the rows select into.
    public let artboard: String

    /// The settled tree rows, in document order.
    public let rows: [TreeRow]

    /// The document revision the rows were read at.
    public let revision: String

    /// The file's id.
    public let file: String

    /// The current view state.
    public let state: ViewState

    /// For each node id, the identities that touched it inside the recency window.
    public let editors: [String: [String]]

    /// A revision, shortened for a header that has one line.
    ///
    /// The full string is on the row's `title`, and the footer of a selected node
    /// carries it in full, so the short form never has to be pasted anywhere.
    ///
    /// - Parameter revision: The full revision.
    /// - Returns: The first and last four characters, joined by an ellipsis.
    static func shortRevision(_ revision: String) -> String {
        guard revision.count > 12 else { return revision }
        return "\(revision.prefix(4))…\(revision.suffix(4))"
    }

    public var body: some HTML {
        section(.class("v-panel v-outline"), .id(ViewerLink.Fragment.outline.target)) {
            header(.class("v-panel-head")) {
                h2(.class("v-panel-title")) { "Outline" }
                span(.class("v-panel-note"), .title(revision)) { "rev \(Self.shortRevision(revision))" }
            }
            if rows.isEmpty {
                p(.class("v-empty-note")) { "This file has no nodes to list." }
            } else {
                div(.class("v-outline-rows")) {
                    for row in rows {
                        OutlineRow(
                            row: row,
                            file: file,
                            artboard: artboard,
                            state: state,
                            editors: editors[row.id] ?? []
                        )
                    }
                }
            }
        }
    }
}
