//
//  FileEmptyPage.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// `GET /files/{file}` for a file that has no top-level frames yet: a real page that
/// says so and waits, rather than a 404.
///
/// Every `woodcase new` passes through this state, and an agent that registers its
/// variables before its first frame sits in it for minutes — so it is a first
/// impression, not an edge case. It used to be a raw JSON 404, because the page picked
/// the first artboard to showcase and, with none, asked the render endpoint for the
/// empty id.
///
/// Shaped like the dashboard's ``EmptyPage`` — a centered title, one muted lede, the
/// command that makes something appear — because they are the same atom answering the
/// same question one level apart: *there is nothing here yet, and here is what to type.*
///
/// ## It replaces itself
///
/// The section carries `data-empty-file`, so `viewer.js` knows which file this page is
/// waiting on: a `change` naming that file with artboards in it means the first frame
/// has landed, and the page reloads into the map. A fragment swap could not do it —
/// the page that answers next is a different page, with a different body layout — so the
/// reload *is* the update, and it needs nobody to press anything.
public struct FileEmptyPage: HTML {
    /// Creates the page.
    ///
    /// - Parameters:
    ///   - file: The file being watched.
    ///   - variables: The document's variables — often the only thing in it at this
    ///     point, and worth saying so the page is not a flat "nothing here".
    ///   - axes: The document's theme axes, for the bar's theme picker.
    ///   - presence: Who has been writing.
    ///   - state: The current view state.
    ///   - clock: The moment the page is rendered for.
    public init(
        file: ViewerFile,
        variables: [ViewerVariable],
        axes: [String: [String]],
        presence: [ViewerPresence.Identity],
        state: ViewState,
        clock: ViewerClock
    ) {
        self.file = file
        self.variables = variables
        self.axes = axes
        self.presence = presence
        self.state = state
        self.clock = clock
    }

    /// The file being watched.
    public let file: ViewerFile

    /// The document's variables.
    public let variables: [ViewerVariable]

    /// The document's theme axes.
    public let axes: [String: [String]]

    /// Who has been writing.
    public let presence: [ViewerPresence.Identity]

    /// The current view state.
    public let state: ViewState

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// The file as the command block spells it — the name a person types, not the id.
    var command: String {
        file.url.lastPathComponent
    }

    /// What the mono footnote says: that this page is live, and what the file does hold.
    var note: String {
        let count = variables.count
        let tokens = count == 1 ? "1 variable" : "\(count) variables"
        return "watching for changes · \(file.path) · \(tokens), no frames"
    }

    public var body: some HTML {
        ViewerDocument(title: "\(file.name) · no artboards yet", layout: .empty) {
            TopBar(
                crumbs: [TopBar.Crumb(label: file.name)],
                presence: presence,
                clock: clock,
                axes: axes,
                state: state,
                action: ViewerLink.file(file.id),
                // No artboard to follow anyone to and none to present, which is the
                // same fact the bar reads off `files`.
                subject: .files
            )
            main(.class("v-main")) {
                section(.class("v-empty"), .data("empty-file", value: file.id)) {
                    h1(.class("v-empty-title")) { "No artboards yet" }
                    p(.class("v-empty-lede")) {
                        "The first top-level frame in this file appears here, the moment it is written."
                    }
                    // The fade is the block's overflow affordance and paints over its
                    // right edge, so the block needs a positioned parent to hang it on.
                    div(.class("v-empty-block")) {
                        pre(.class("v-mono v-empty-commands")) {
                            code(.class("is-primary")) {
                                "echo '{\"type\":\"frame\",\"name\":\"Screen\",\"width\":390,\"height\":844}' "
                                    + "| woodcase add \(command) document -F -"
                            }
                            code { "woodcase tree \(command)" }
                        }
                        span(.class("v-empty-fade"), .custom(name: "aria-hidden", value: "true")) {}
                    }
                    p(.class("v-mono v-empty-note")) { note }
                }
            }
        }
    }
}
