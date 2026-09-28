//
//  PreviewCanvas.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// `GET /preview/{component}` — one component with every state it declares, stacked.
///
/// This is the page the previews exist for: the states side by side, each under its
/// name, each with the note saying what to look at, each in the production surface it
/// belongs on. Reading down it is the review.
///
/// Every state carries an anchor (`#<state-slug>`) and a link to its own page, so a
/// defect found here is reported as a URL rather than as "the third one down".
///
/// A ``PreviewFrame/page`` state is a link and its note rather than a nested render: a
/// whole page is its own ``ViewerDocument``, and a document cannot nest a document. The
/// single-state route serves those whole.
public struct PreviewCanvas: HTML {
    /// Creates a canvas.
    ///
    /// - Parameters:
    ///   - component: The component to show, with the states it declares.
    ///   - clock: The moment the page is rendered for.
    public init(component: PreviewComponent, clock: ViewerClock) {
        self.component = component
        self.clock = clock
    }

    /// The component being shown.
    public let component: PreviewComponent

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    public var body: some HTML {
        ViewerDocument(title: "\(component.title) · previews", layout: .preview) {
            TopBar(
                crumbs: [
                    TopBar.Crumb(label: "Previews", href: ViewerLink.previews),
                    TopBar.Crumb(label: component.title),
                ],
                presence: [],
                clock: clock,
                subject: .previews
            )
            main(.class("v-main")) {
                section(.class("v-preview-canvas"), .id("v-preview-canvas")) {
                    header(.class("v-section-head")) {
                        div(.class("v-section-titles")) {
                            h1(.class("v-section-title")) { component.title }
                            p(.class("v-section-subtitle")) { PreviewProse(component.blurb) }
                        }
                        span(.class("v-mono v-section-note")) { component.source }
                    }
                    for state in component.states {
                        article(.class("v-preview-state"), .id(state.slug)) {
                            h2(.class("v-preview-state-name")) {
                                a(.class("v-preview-anchor"), .href("#\(state.slug)"), .title("Link to this state")) {
                                    "#"
                                }
                                state.name
                            }
                            p(.class("v-preview-note")) { PreviewProse(state.note) }
                            a(
                                .class("v-mono v-preview-permalink"),
                                .href(ViewerLink.previewState(component: component.slug, state: state.slug))
                            ) { ViewerLink.previewState(component: component.slug, state: state.slug) }
                            if state.frame == .page {
                                p(.class("v-preview-whole")) {
                                    "A whole page in its own document — open it on its own to see it. "
                                        + "A document cannot nest a document, so it is not drawn here."
                                }
                            } else {
                                PreviewFrameBox(state: state)
                            }
                        }
                    }
                }
            }
        }
    }
}
