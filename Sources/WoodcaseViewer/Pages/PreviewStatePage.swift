//
//  PreviewStatePage.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// `GET /preview/{component}/{state}` — one state, alone, on a page of its own.
///
/// This is the URL a review shot opens: `sleepy shot .../preview/avatar/small`. One
/// state per page rather than a crop of the canvas, because a crop has to be described
/// ("the third one down") and a URL does not — the shot, the defect report and the fix
/// all name the same string.
///
/// The note travels with it. A picture sent to a reviewer with no caption asks them to
/// work out what they are looking at, and the note is the one sentence that says.
///
/// A ``PreviewFrame/page`` state never reaches this type: it is already a whole
/// ``ViewerDocument``, so the route serves it verbatim instead of wrapping it in a
/// second one.
public struct PreviewStatePage: HTML {
    /// Creates the page.
    ///
    /// - Parameters:
    ///   - component: The component the state belongs to, for the trail and the source.
    ///   - state: The state to show. Must not be framed as ``PreviewFrame/page``.
    ///   - clock: The moment the page is rendered for.
    public init(component: PreviewComponent, state: PreviewState, clock: ViewerClock) {
        self.component = component
        self.state = state
        self.clock = clock
    }

    /// The component the state belongs to.
    public let component: PreviewComponent

    /// The state being shown.
    public let state: PreviewState

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    public var body: some HTML {
        ViewerDocument(title: "\(state.name) · \(component.title) · previews", layout: .preview) {
            TopBar(
                crumbs: [
                    TopBar.Crumb(label: "Previews", href: ViewerLink.previews),
                    TopBar.Crumb(label: component.title, href: ViewerLink.previewComponent(component.slug)),
                    TopBar.Crumb(label: state.name),
                ],
                presence: [],
                clock: clock,
                subject: .previews
            )
            main(.class("v-main")) {
                section(.class("v-preview-canvas"), .id("v-preview-state")) {
                    header(.class("v-section-head")) {
                        div(.class("v-section-titles")) {
                            h1(.class("v-section-title")) { state.name }
                            p(.class("v-section-subtitle")) { PreviewProse(state.note) }
                        }
                        span(.class("v-mono v-section-note")) { component.source }
                    }
                    article(.class("v-preview-state"), .id(state.slug)) {
                        PreviewFrameBox(state: state)
                    }
                }
            }
        }
    }
}
