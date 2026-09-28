//
//  ArtboardPage.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// `GET /files/{file}/artboards/{artboard}` — one artboard, with the outline beside it
/// and the feed beside that. Also `GET /files/{file}` for a file with only one artboard,
/// where a map of a single box would be a page you would only ever click through.
///
/// The render gets the **whole** canvas pane: no band of other artboards above it — that
/// band made every box too small to read and is now a page of its own (``MapPage``) — and
/// no generated code beside it, which is a tab in the right pane (``ViewerTab/code``).
/// What replaces the band is navigation that was already here — the breadcrumb's file
/// name leads back up to the map, the selection footer steps `‹ n of N ›` to the
/// artboards either side, and ← / → do the same from the keyboard.
///
/// Served whole: the outline rows, the variables, the activity, the presence, and the
/// selected node already outlined over the render. Nothing on it waits for the script.
/// The script's job is to keep it live and to move the boxes; with it switched off the
/// page is a correct, navigable view of the file.
public struct ArtboardPage: HTML {
    /// Creates a page.
    ///
    /// - Parameters:
    ///   - file: The file being shown.
    ///   - artboard: The artboard being shown.
    ///   - artboards: Every artboard of the file, for the bird's-eye map.
    ///   - layout: Where every node inside the artboard sits.
    ///   - layoutJSON: That layout, already encoded.
    ///   - rows: The settled tree rows for the outline.
    ///   - variables: The document's variables.
    ///   - axes: The document's theme axes.
    ///   - events: The file's recent activity, oldest first.
    ///   - presence: Who has been writing.
    ///   - markers: Recent edits to draw over the render.
    ///   - editors: For each node id, who touched it inside the recency window.
    ///   - details: The selected node's details, or `nil` when nothing is selected.
    ///   - unresolved: The `?node=` address that named nothing, when one did.
    ///   - targets: The generated files this document produces for this artboard.
    ///     Empty offers only the image formats, which is the honest answer for a
    ///     preview that ran no emitter.
    ///   - code: The generated file the right pane's Code tab shows, or `nil` when the
    ///     emitter writes none for this artboard.
    ///   - state: The current view state.
    ///   - clock: The moment the page is rendered for.
    public init(
        file: ViewerFile,
        artboard: Artboard,
        artboards: [Artboard],
        layout: ArtboardLayout,
        layoutJSON: String,
        rows: [TreeRow],
        variables: [ViewerVariable],
        axes: [String: [String]],
        events: [ActivityEvent],
        presence: [ViewerPresence.Identity],
        markers: [EditMarker],
        editors: [String: [String]],
        details: NodeDetails? = nil,
        unresolved: String? = nil,
        targets: [ViewerCodeTarget] = [],
        code: ArtboardCode? = nil,
        state: ViewState,
        clock: ViewerClock
    ) {
        self.file = file
        self.artboard = artboard
        self.artboards = artboards
        self.layout = layout
        self.layoutJSON = layoutJSON
        self.rows = rows
        self.variables = variables
        self.axes = axes
        self.events = events
        self.presence = presence
        self.markers = markers
        self.editors = editors
        self.details = details
        self.unresolved = unresolved
        self.targets = targets
        self.code = code
        self.state = state
        self.clock = clock
    }

    /// The file being shown.
    public let file: ViewerFile
    /// The artboard being shown.
    public let artboard: Artboard
    /// Every artboard of the file.
    public let artboards: [Artboard]
    /// Where every node inside the artboard sits.
    public let layout: ArtboardLayout
    /// That layout, already encoded.
    public let layoutJSON: String
    /// The settled tree rows for the outline.
    public let rows: [TreeRow]
    /// The document's variables.
    public let variables: [ViewerVariable]
    /// The document's theme axes.
    public let axes: [String: [String]]
    /// The file's recent activity, oldest first.
    public let events: [ActivityEvent]
    /// Who has been writing.
    public let presence: [ViewerPresence.Identity]
    /// Recent edits to draw over the render.
    public let markers: [EditMarker]
    /// For each node id, who touched it inside the recency window.
    public let editors: [String: [String]]
    /// The selected node's details, or `nil` when nothing is selected.
    public let details: NodeDetails?
    /// The `?node=` address that named nothing, when one did.
    public let unresolved: String?
    /// The generated files this document produces for this artboard.
    public let targets: [ViewerCodeTarget]
    /// The generated file the right pane's Code tab shows.
    public let code: ArtboardCode?
    /// The current view state.
    public let state: ViewState
    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// The page's own path, which the theme forms submit to and the script pushes.
    var path: String {
        ViewerLink.artboard(file: file.id, artboard: artboard.id)
    }

    /// The trail: the file's map, and this artboard.
    ///
    /// It starts at the file, not at the list of files: the brand beside it is a link to
    /// the root, and a trail whose first step said "Files" was saying the same thing
    /// twice while pushing the part you care about — the artboard's name — off the end.
    ///
    /// The file crumb leads to the map and says so with a glyph. It is also where the
    /// script hangs a dot when something changed in an artboard other than this one —
    /// the news is *up there*, and this is the way up.
    var crumbs: [TopBar.Crumb] {
        [
            TopBar.Crumb(
                label: file.name,
                href: ViewerLink.file(file.id),
                leads: artboards.count > 1 ? .map : nil
            ),
            TopBar.Crumb(label: artboard.name ?? artboard.id),
        ]
    }

    public var body: some HTML {
        ViewerDocument(title: "\(file.name) · \(artboard.name ?? artboard.id)", layout: .artboard) {
            TopBar(
                crumbs: crumbs,
                presence: presence,
                clock: clock,
                axes: axes,
                state: state,
                action: path,
                subject: .artboard
            )
            main(.class("v-main"), .id("v-main")) {
                aside(.class("v-side v-side-left"), .id("v-left")) {
                    OutlinePanel(
                        rows: rows,
                        revision: layout.revision,
                        file: file.id,
                        artboard: artboard.id,
                        state: state,
                        editors: editors
                    )
                    PaneGrip(name: "lower", property: "--v-row-lower", axis: .rows, edge: .after)
                    VariablesPanel(variables: variables, axes: axes, clock: clock)
                }
                PaneGrip(name: "left", property: "--v-col-left", axis: .columns, edge: .before)
                section(.class("v-canvas")) {
                    div(.class("v-canvas-body"), .id("v-canvas-body")) {
                        RenderRegion(
                            file: file.id,
                            artboard: artboard,
                            artboards: artboards,
                            layout: layout,
                            layoutJSON: layoutJSON,
                            state: state,
                            markers: markers,
                            clock: clock
                        )
                    }
                }
                PaneGrip(name: "right", property: "--v-col-right", axis: .columns, edge: .after)
                RightPane(
                    file: file.id,
                    artboard: artboard,
                    details: details,
                    unresolved: unresolved,
                    targets: targets,
                    code: code,
                    events: events,
                    state: state,
                    clock: clock
                )
            }
            // Outside `main`, because presentation lifts the canvas out of that grid
            // entirely, and outside ``RenderRegion``, because the region is replaced on
            // every change and every step and the hint must not flash again each time.
            PresentationHint()
        }
    }
}
