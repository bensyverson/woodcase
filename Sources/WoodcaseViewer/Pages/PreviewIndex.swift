//
//  PreviewIndex.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// `GET /preview` — every component that declares previews, with its blurb, how many
/// states it has, and the file to open when one of them looks wrong.
///
/// The index is a table of contents, not a gallery: rendering twenty components' worth
/// of states on one page would be slower to load than the canvases it links to and
/// harder to read than any of them. What it owes a reader is the shortest path to the
/// right canvas, so every row is a link and every row names its source.
///
/// A pure function of the components it is handed — no file, no log, no cache — which
/// is what lets `woodcase preview` serve it over an empty index and `woodcase serve`
/// serve the identical bytes beside a live document.
public struct PreviewIndex: HTML {
    /// Creates the index.
    ///
    /// - Parameters:
    ///   - components: The components to list, in the order they should be read.
    ///   - clock: The moment the page is rendered for.
    public init(components: [PreviewComponent], clock: ViewerClock) {
        self.components = components
        self.clock = clock
    }

    /// The components to list.
    public let components: [PreviewComponent]

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// How many states the listed components declare between them.
    var stateCount: Int {
        components.reduce(0) { $0 + $1.states.count }
    }

    public var body: some HTML {
        ViewerDocument(title: "Previews · woodcase", layout: .preview) {
            TopBar(crumbs: [TopBar.Crumb(label: "Previews")], presence: [], clock: clock, subject: .previews)
            main(.class("v-main")) {
                section(.class("v-preview-index"), .id("v-preview-index")) {
                    header(.class("v-section-head")) {
                        div(.class("v-section-titles")) {
                            h1(.class("v-section-title")) { "Previews" }
                            p(.class("v-section-subtitle")) {
                                "Every component of the viewer, in the states worth looking at."
                            }
                        }
                        span(.class("v-mono v-section-note")) {
                            "\(components.count) \(components.count == 1 ? "component" : "components")"
                                + " · \(stateCount) \(stateCount == 1 ? "state" : "states")"
                        }
                    }
                    ul(.class("v-preview-list")) {
                        for component in components {
                            li(.class("v-preview-entry")) {
                                a(
                                    .class("v-preview-entry-link"),
                                    .href(ViewerLink.previewComponent(component.slug))
                                ) { component.title }
                                span(.class("v-mono v-preview-count")) {
                                    "\(component.states.count) "
                                        + (component.states.count == 1 ? "state" : "states")
                                }
                                p(.class("v-preview-blurb")) { PreviewProse(component.blurb) }
                                span(.class("v-mono v-preview-source")) { component.source }
                            }
                        }
                    }
                }
            }
        }
    }
}
