//
//  MapPage.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// `GET /files/{file}` — the whole file at a glance, and the page you land on.
///
/// The canvas pane is the bird's-eye ``ArtboardMap``: every artboard drawn as a real
/// low-res render at the position the file gives it. The left pane lists the same
/// artboards as rows, because a map answers *where* and a list answers *what there is*,
/// and a file you have not seen before wants both. Clicking either drills into that
/// artboard, where the render then gets the whole pane.
///
/// A file with a single artboard never gets this page: a map of one box is a page you
/// would only ever click through, so ``ArtboardPageBuilder`` sends it straight to the
/// artboard.
///
/// The right pane keeps the activity feed and nothing else. Details describes a selected
/// node and Export writes one artboard; on a page that is looking at all of them and none
/// in particular, both would open on an apology.
public struct MapPage: HTML {
    /// Creates a page.
    ///
    /// - Parameters:
    ///   - file: The file being shown.
    ///   - artboards: Every artboard of the file, in document order.
    ///   - revision: The document revision the page was read at.
    ///   - variables: The document's variables.
    ///   - axes: The document's theme axes.
    ///   - events: The file's recent activity, oldest first.
    ///   - presence: Who has been writing.
    ///   - editors: For each artboard id, who touched something inside it inside the
    ///     recency window.
    ///   - state: The current view state.
    ///   - clock: The moment the page is rendered for.
    public init(
        file: ViewerFile,
        artboards: [Artboard],
        revision: String,
        variables: [ViewerVariable],
        axes: [String: [String]],
        events: [ActivityEvent],
        presence: [ViewerPresence.Identity],
        editors: [String: [String]] = [:],
        state: ViewState,
        clock: ViewerClock
    ) {
        self.file = file
        self.artboards = artboards
        self.revision = revision
        self.variables = variables
        self.axes = axes
        self.events = events
        self.presence = presence
        self.editors = editors
        self.state = state
        self.clock = clock
    }

    /// The file being shown.
    public let file: ViewerFile
    /// Every artboard of the file, in document order.
    public let artboards: [Artboard]
    /// The document revision the page was read at.
    public let revision: String
    /// The document's variables.
    public let variables: [ViewerVariable]
    /// The document's theme axes.
    public let axes: [String: [String]]
    /// The file's recent activity, oldest first.
    public let events: [ActivityEvent]
    /// Who has been writing.
    public let presence: [ViewerPresence.Identity]
    /// For each artboard id, who touched something inside it recently.
    public let editors: [String: [String]]
    /// The current view state.
    public let state: ViewState
    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// The page's own path, which the theme and follow forms submit to.
    var path: String {
        ViewerLink.file(file.id)
    }

    public var body: some HTML {
        ViewerDocument(title: "\(file.name) · map", layout: .artboard) {
            TopBar(
                crumbs: [TopBar.Crumb(label: file.name)],
                presence: presence,
                clock: clock,
                axes: axes,
                state: state,
                action: path,
                subject: .map
            )
            main(.class("v-main"), .id("v-main")) {
                aside(.class("v-side v-side-left"), .id("v-left")) {
                    ArtboardOutline(
                        artboards: artboards,
                        revision: revision,
                        file: file.id,
                        state: state,
                        editors: editors
                    )
                    PaneGrip(name: "lower", property: "--v-row-lower", axis: .rows, edge: .after)
                    VariablesPanel(variables: variables, axes: axes, clock: clock)
                }
                PaneGrip(name: "left", property: "--v-col-left", axis: .columns, edge: .before)
                section(.class("v-canvas")) {
                    ArtboardMap(
                        file: file.id,
                        artboards: artboards,
                        state: state,
                        editors: editors
                    )
                }
                PaneGrip(name: "right", property: "--v-col-right", axis: .columns, edge: .after)
                RightPane(
                    file: file.id,
                    artboard: nil,
                    details: nil,
                    targets: [],
                    events: events,
                    state: state,
                    clock: clock
                )
            }
            // `f` works here too — it is an "any" key — and a chrome-less map with no
            // way out said would be a trap, so the map carries the same hint even though
            // the bar offers it no button.
            PresentationHint()
        }
    }
}
