//
//  RightPane.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The right column: a tab bar over Activity, Details, Export and Code.
///
/// Every panel is rendered on every page and the tab only decides which one the
/// stylesheet shows. That is not laziness — it is what makes the tabs work with the
/// script off (they are real links to `?tab=`), what lets a fragment swap land in a
/// panel nobody is looking at, and what makes switching tabs instant rather than a round
/// trip. Four panels of a local file are cheap; a tab that has to fetch before it can
/// be read is not.
///
/// The `data-tab` attribute is on the `<aside>`, so the whole pane is one CSS selector
/// away from showing the right panel and the script's job is to set one attribute.
///
/// ## Code is a tab, not a second canvas
///
/// The generated file used to open as the right-hand half of a split canvas, behind a
/// switch at the end of this bar. It cost the render a third of its width whenever it
/// was open, and it answered a question of exactly the shape the other tabs answer —
/// *what is this artboard, told another way*. So it is a pill like the rest. A page with
/// no artboard generates nothing, and gets no Code tab, for the same reason it gets no
/// Details and no Export.
public struct RightPane: HTML {
    /// Creates a pane.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard on screen, which Export writes and Code shows — or
    ///     `nil` on the map page, which is looking at all of them and none.
    ///   - details: The selected node's details, or `nil` when nothing is selected.
    ///   - unresolved: The `?node=` address that named nothing, when one did.
    ///   - targets: The generated files this document produces for this artboard.
    ///   - code: The generated file the Code tab shows, or `nil` when the emitter writes
    ///     none for this artboard.
    ///   - events: The file's recent activity, oldest first.
    ///   - state: The current view state, which decides the tab and the links.
    ///   - clock: The moment the page is rendered for.
    public init(
        file: String,
        artboard: Artboard?,
        details: NodeDetails?,
        unresolved: String? = nil,
        targets: [ViewerCodeTarget],
        code: ArtboardCode? = nil,
        events: [ActivityEvent],
        state: ViewState,
        clock: ViewerClock
    ) {
        self.file = file
        self.artboard = artboard
        self.details = details
        self.unresolved = unresolved
        self.targets = targets
        self.code = code
        self.events = events
        self.state = state
        self.clock = clock
    }

    /// The artboard on screen, or `nil` on the map page.
    public let artboard: Artboard?

    /// The file's id.
    public let file: String

    /// The selected node's details, or `nil` when nothing is selected.
    public let details: NodeDetails?

    /// The `?node=` address that named nothing, when one did.
    public let unresolved: String?

    /// The generated files this document produces for this artboard.
    public let targets: [ViewerCodeTarget]

    /// The generated file the Code tab shows, or `nil` when there is none.
    public let code: ArtboardCode?

    /// The file's recent activity, oldest first.
    public let events: [ActivityEvent]

    /// The current view state.
    public let state: ViewState

    /// The moment the page is rendered for.
    public let clock: ViewerClock

    /// Which panels this pane can show.
    ///
    /// Details describes a selected node, and Export and Code both answer about one
    /// artboard; the map page has none of the three — so it shows Activity alone rather
    /// than three tabs that would open on an apology.
    var tabs: [ViewerTab] {
        artboard == nil ? [.activity] : ViewerTab.allCases
    }

    /// Which panel is showing, clamped to the ones this pane has.
    var tab: ViewerTab {
        tabs.contains(state.tab) ? state.tab : .fallback
    }

    public var body: some HTML {
        aside(
            .class("v-side v-side-right"),
            .id("v-right"),
            .data("tab", value: tab.rawValue)
        ) {
            nav(.class("v-tabbar")) {
                for tab in tabs {
                    a(
                        .class("v-tab"),
                        .data("tab", value: tab.rawValue),
                        .href(link(state.showing(tab)))
                    ) { tab.label }
                        .attributes(.class("is-current"), when: tab == self.tab)
                }
            }
            div(.class("v-pane"), .data("pane", value: ViewerTab.activity.rawValue)) {
                ActivityFeed(
                    events: events,
                    clock: clock,
                    scope: "this file · all identities",
                    limit: 40
                )
            }
            if let artboard {
                div(.class("v-pane"), .data("pane", value: ViewerTab.details.rawValue)) {
                    DetailsPanel(details: details, file: file, unresolved: unresolved)
                }
                div(.class("v-pane"), .data("pane", value: ViewerTab.export.rawValue)) {
                    ExportPanel(file: file, artboard: artboard, targets: targets, state: state)
                }
                div(.class("v-pane"), .data("pane", value: ViewerTab.code.rawValue)) {
                    CodePane(
                        file: file,
                        artboard: artboard.id,
                        code: code,
                        targets: targets,
                        state: state
                    )
                }
            }
        }
    }

    /// Where a control in this pane points: the artboard page, or the map when there is
    /// no artboard.
    ///
    /// - Parameter state: The view state the link should open under.
    /// - Returns: The path with its query.
    func link(_ state: ViewState) -> String {
        guard let artboard else { return ViewerLink.file(file, state: state) }
        return ViewerLink.artboard(file: file, artboard: artboard.id, state: state)
    }
}
