//
//  DetailsPanel.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The Details tab: the selected node's attributes, each one marked with where its
/// value came from.
///
/// The row is a codec path, a value, and a mark — and the mark is the point. Two nodes
/// showing `#2FBF6F` are not the same node if one of them wrote the hex and the other
/// wrote `$accent`; two instances of one component are not the same if one of them
/// overrides the label. The mark is what turns "here is a value" into "here is where to
/// go and change it".
///
/// Also the fragment served at `GET /files/{file}/details`.
public struct DetailsPanel: HTML {
    /// Creates a panel.
    ///
    /// - Parameters:
    ///   - details: The selected node's details, or `nil` when nothing is selected.
    ///   - file: The file's id, for the empty note's wording.
    ///   - unresolved: The `?node=` address that named nothing, when one did.
    public init(details: NodeDetails?, file: String, unresolved: String? = nil) {
        self.details = details
        self.file = file
        self.unresolved = unresolved
    }

    /// The selected node's details, or `nil` when nothing is selected.
    public let details: NodeDetails?

    /// The file's id.
    public let file: String

    /// The `?node=` address that named nothing.
    ///
    /// A stale link — a node renamed since the URL was copied — must not take the whole
    /// page down with it, so the artboard still renders and *this* is where the page
    /// says the address went nowhere. Silence would leave a reader believing the node is
    /// simply unselected.
    public let unresolved: String?

    public var body: some HTML {
        section(.class("v-panel v-details"), .id(ViewerLink.Fragment.details.target)) {
            header(.class("v-panel-head")) {
                h2(.class("v-panel-title")) { "Details" }
                if let details {
                    span(.class("v-panel-note")) { details.type }
                }
            }
            if let details {
                Head(details: details)
                if details.rows.isEmpty {
                    p(.class("v-empty-note")) { "This node sets no properties of its own." }
                } else {
                    div(.class("v-detail-rows")) {
                        for row in details.rows {
                            Row(row: row)
                        }
                    }
                }
            } else if let unresolved {
                p(.class("v-empty-note v-detail-unresolved")) {
                    "'\(unresolved)' names no node in this file. "
                        + "The outline lists every node; a renamed one keeps its id."
                }
            } else {
                p(.class("v-empty-note")) {
                    "Select a node — in the outline or on the render — to see what it carries."
                }
            }
        }
    }

    /// The node itself: what to call it, its id, and the instance it sits inside.
    ///
    /// Nested rather than filed on its own: it has no use outside this panel.
    struct Head: HTML {
        /// The details to draw.
        let details: NodeDetails

        var body: some HTML {
            div(.class("v-detail-head")) {
                span(.class("v-detail-name")) { details.label }
                IdChip(id: details.id, extraClasses: "v-mono v-detail-id")
                span(.class("v-mono v-detail-path")) { details.path }
                if let instance = details.instance {
                    span(.class("v-detail-instance"), .title("Inside component instance \(instance)")) {
                        "in instance"
                    }
                    IdChip(id: instance, extraClasses: "v-mono")
                }
            }
        }
    }

    /// One property: its codec path, its value, and its mark.
    struct Row: HTML {
        /// The row to draw.
        let row: NodeDetail

        var body: some HTML {
            div(
                .class("v-row v-detail-row"),
                .data("path", value: row.path),
                .data("origin", value: row.origin.rawValue)
            ) {
                span(.class("v-mono v-detail-key"), .title("\(row.path)  (key: \(row.key))")) {
                    row.path
                }
                span(.class("v-detail-value")) { row.value }
                span(.class("v-detail-origin"), .data("origin", value: row.origin.rawValue)) {
                    row.originLabel
                }
                if let source = row.source {
                    span(
                        .class("v-mono v-detail-source"),
                        .title("Overridden by instance \(source.instance); the component says \(source.was)")
                    ) {
                        "from \(source.path) · was \(source.was)"
                    }
                }
            }
            .attributes(.data("instance", value: row.source?.instance ?? ""), when: row.source != nil)
        }
    }
}
