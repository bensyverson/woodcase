//
//  CodePane.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The right pane's Code tab: what `woodcase generate react` writes for the artboard on
/// screen.
///
/// It is one panel of ``RightPane``, which says why it is a tab rather than half the
/// canvas.
///
/// The language picker is a `GET` form aimed at the page, so with the script off it is a
/// navigation to `?lang=` and the pane comes back server-rendered. With the script on it
/// is a change-to-apply dropdown that also remembers the choice in `localStorage`, which
/// is the one piece of state here that is a property of *this browser* rather than of
/// the view: the URL you paste to a colleague should open the artboard, not impose your
/// taste in output files on them.
///
/// Also the fragment served at `GET /files/{file}/artboards/{artboard}/code`.
public struct CodePane: HTML {
    /// Creates a pane.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard's node id.
    ///   - code: The generated file to show, or `nil` when the emitter writes none.
    ///   - targets: The generated files this document produces, for the picker.
    ///   - state: The current view state, which the picker's form carries forward.
    public init(
        file: String,
        artboard: String,
        code: ArtboardCode?,
        targets: [ViewerCodeTarget],
        state: ViewState
    ) {
        self.file = file
        self.artboard = artboard
        self.code = code
        self.targets = targets
        self.state = state
    }

    /// The file's id.
    public let file: String

    /// The artboard's node id.
    public let artboard: String

    /// The generated file to show, or `nil` when the emitter writes none.
    public let code: ArtboardCode?

    /// The generated files this document produces.
    public let targets: [ViewerCodeTarget]

    /// The current view state.
    public let state: ViewState

    /// Which target is showing — what the script reads back to compare with what the
    /// browser remembers.
    var showing: ViewerCodeTarget {
        code?.target ?? state.lang ?? .react
    }

    /// The page the picker submits to.
    var action: String {
        "/files/\(ViewerLink.escape(file))/artboards/\(ViewerLink.escape(artboard))"
    }

    public var body: some HTML {
        section(
            .class("v-code"),
            .id(ViewerLink.Fragment.code.target),
            .data("lang", value: showing.rawValue),
            .data("file", value: file),
            .data("artboard", value: artboard)
        ) {
            header(.class("v-code-head")) {
                form(.class("v-code-form"), .method(.get), .action(action)) {
                    if let node = state.node {
                        input(.type(.hidden), .name("node"), .value(node))
                    }
                    if !state.theme.isEmpty {
                        input(
                            .type(.hidden),
                            .name("theme"),
                            .value(ThemeQuery.canonical(state.theme))
                        )
                    }
                    // Always this pane's own tab, never the one that happens to be
                    // showing: with the script off, submitting the picker is a
                    // navigation, and it has to land back on the code you asked for.
                    input(.type(.hidden), .name("tab"), .value(ViewerTab.code.rawValue))
                    select(.class("v-code-lang"), .name("lang")) {
                        for target in targets {
                            option(.value(target.rawValue)) { target.label }
                                .attributes(.selected, when: target == showing)
                        }
                    }
                    button(.class("v-go"), .type(.submit)) { "show" }
                }
                if let code {
                    span(.class("v-mono v-code-path")) { code.path }
                }
            }
            if let code {
                pre(.class("v-code-body"), .data("syntax", value: code.target.syntax)) {
                    code.text
                }
            } else {
                p(.class("v-empty-note")) {
                    Elementary.code { "woodcase generate react" }
                    " writes no \(showing.label) file for this artboard. A component "
                        + "definition and a top-level frame each generate a .tsx; a placed "
                        + "instance generates none."
                }
            }
        }
    }
}
