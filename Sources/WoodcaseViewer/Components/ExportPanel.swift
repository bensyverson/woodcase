//
//  ExportPanel.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The Export tab: this artboard as a file, in a format the CLI already writes.
///
/// A `GET` form rather than a set of links, so choosing a format and a size and pressing
/// the button *is* the download — no script, no assembled URL, and the address bar shows
/// exactly the request an agent can repeat with `curl`. The endpoint answers with
/// `Content-Disposition: attachment`, which is what makes a navigation a save.
///
/// The formats are ``ViewerExportFormat/allCases`` and nothing else: PNG and PDF because
/// `render` and `shot` write them, and the generated files because `generate react`
/// writes those. There is no SVG and no whole-package archive, because there is no verb
/// behind either.
public struct ExportPanel: HTML {
    /// Creates a panel.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard being exported.
    ///   - targets: The generated files this document actually produces for this
    ///     artboard — a `states.css` is offered only when a component declares states.
    ///   - state: The current view state; its theme rides along as a hidden field so an
    ///     export matches what is on screen.
    public init(file: String, artboard: Artboard, targets: [ViewerCodeTarget], state: ViewState) {
        self.file = file
        self.artboard = artboard
        self.targets = targets
        self.state = state
    }

    /// The file's id.
    public let file: String

    /// The artboard being exported.
    public let artboard: Artboard

    /// The generated files this document produces for this artboard.
    public let targets: [ViewerCodeTarget]

    /// The current view state.
    public let state: ViewState

    /// The formats the picker offers: the images always, the generated files this
    /// document actually writes.
    var formats: [ViewerExportFormat] {
        [.png, .pdf] + targets.map(ViewerExportFormat.code)
    }

    /// The endpoint the form submits to, without a query — the browser builds that from
    /// the controls.
    var action: String {
        "/files/\(ViewerLink.escape(file))/artboards/\(ViewerLink.escape(artboard.id))/export"
    }

    public var body: some HTML {
        section(.class("v-panel v-export"), .id("v-export")) {
            header(.class("v-panel-head")) {
                h2(.class("v-panel-title")) { "Export" }
                span(.class("v-panel-note")) {
                    "\(OutlineRow.number(artboard.width))×\(OutlineRow.number(artboard.height)) pt"
                }
            }
            form(.class("v-export-form"), .method(.get), .action(action)) {
                if !state.theme.isEmpty {
                    input(
                        .type(.hidden),
                        .name("theme"),
                        .value(ThemeQuery.canonical(state.theme))
                    )
                }
                label(.class("v-export-field"), .for("v-export-format")) {
                    span(.class("v-export-label")) { "Format" }
                    select(.id("v-export-format"), .class("v-export-format"), .name("format")) {
                        for format in formats {
                            option(.value(format.query)) { format.label }
                                .attributes(.selected, when: format == .png)
                        }
                    }
                }
                label(.class("v-export-field"), .for("v-export-scale")) {
                    span(.class("v-export-label")) { "Scale" }
                    select(.id("v-export-scale"), .class("v-export-scale"), .name("scale")) {
                        for scale in Self.scales {
                            option(.value(String(scale))) { "\(scale)×" }
                                .attributes(.selected, when: scale == 2)
                        }
                    }
                }
                label(.class("v-export-field"), .for("v-export-max")) {
                    span(.class("v-export-label")) { "or longest edge" }
                    input(
                        .id("v-export-max"),
                        .class("v-export-max"),
                        .type(.number),
                        .name("max"),
                        .custom(name: "min", value: "1"),
                        .custom(name: "placeholder", value: "points")
                    )
                }
                // Deliberately not `.v-go`: that class is the fallback submit a scripted
                // page hides, and this button *is* the download on every page.
                button(.class("v-export-go"), .type(.submit)) { "Download" }
            }
            // The commands are in `<code>`, the mono voice anything an agent would type
            // takes — not Markdown backticks, which the page would print as characters.
            p(.class("v-empty-note")) {
                "PNG and PDF are what "
                code { "render" }
                " and "
                code { "shot" }
                " write; the rest is what "
                code { "generate react" }
                " writes. Scale and longest edge apply to the PNG only."
            }
        }
    }

    /// The scales offered, matching what a design tool's export sheet offers and what
    /// `render --scale` takes.
    static let scales = [1, 2, 3]
}
