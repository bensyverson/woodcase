//
//  ViewState.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// What you are looking at, as a value — the selection, the theme pins, and how much of
/// the tree is showing.
///
/// The viewer has real routes and no client-side state: everything a page shows that is
/// not the file itself lives in the query, so a URL describes what you see, back and
/// forward work, and a link an agent pastes reopens exactly this view.
///
/// ```text
/// /files/a1b2c3?node=Vr7Kd&theme=Mode%3ADark&depth=3
/// ```
///
/// ``query`` is the one place that spelling is decided, so every link on the page — and
/// every fragment request the script makes — agrees on it.
public struct ViewState: Friendly {
    /// Creates a view state.
    ///
    /// - Parameters:
    ///   - node: The selected node's id or address, or `nil` for no selection.
    ///   - theme: Theme axes pinned over the document's defaults.
    ///   - depth: How many levels of tree to list, or `nil` for all of them.
    ///   - follow: Whose writes move the page, or ``Follow/nobody``.
    ///   - tab: Which of the right pane's panels is showing, or `nil` to let the
    ///     selection decide — a state with a node selected opens on Details, one
    ///     without opens on Activity.
    ///   - lang: Which generated file the code pane is showing, or `nil` for its
    ///     default.
    public init(
        node: String? = nil,
        theme: [String: String] = [:],
        depth: Int? = nil,
        follow: Follow = .nobody,
        tab: ViewerTab? = nil,
        lang: ViewerCodeTarget? = nil
    ) {
        self.node = node
        self.theme = theme
        self.depth = depth
        self.follow = follow
        self.tab = tab ?? Self.tab(forSelection: node)
        self.lang = lang
    }

    /// The selected node's id or address, or `nil` for no selection.
    ///
    /// Set through ``selecting(_:)`` rather than assigned: the selection decides the
    /// tab, and a second way to change it would be a second answer to which panel is
    /// showing.
    public private(set) var node: String?

    /// Theme axes pinned over the document's defaults.
    public var theme: [String: String]

    /// How many levels of tree to list, or `nil` for all of them.
    public var depth: Int?

    /// Whose writes move the page, and whether that is switched on.
    public var follow: Follow
    /// Which of the right pane's panels is showing.
    ///
    /// Set through ``showing(_:)`` or, implicitly, ``selecting(_:)``.
    public private(set) var tab: ViewerTab

    /// Which generated file the code pane is showing, or `nil` for its default.
    public var lang: ViewerCodeTarget?

    /// This state with a different selection.
    ///
    /// Selecting a node also moves the right pane to ``ViewerTab/details`` and clearing
    /// the selection moves it back to ``ViewerTab/activity``, because that is the whole
    /// reason the Details tab exists: you selected something to look at it.
    ///
    /// The rule lives here rather than in each caller so every link that selects agrees
    /// — an outline row, a click on the render, and switching artboards (which clears
    /// the selection) all go through this one function. The cost is that a tab you
    /// picked by hand does not survive the next selection; that is the simple rule, and
    /// the tab bar is one click away.
    ///
    /// - Parameter node: The node to select, or `nil` to clear the selection.
    /// - Returns: A copy; the theme pins and the chosen language are kept, because
    ///   selecting a row must not silently drop what you had pinned.
    public func selecting(_ node: String?) -> ViewState {
        var copy = self
        copy.node = node
        copy.tab = Self.tab(forSelection: node)
        return copy
    }

    /// This state showing a different panel of the right pane.
    ///
    /// - Parameter tab: The panel to show.
    /// - Returns: A copy.
    public func showing(_ tab: ViewerTab) -> ViewState {
        var copy = self
        copy.tab = tab
        return copy
    }

    /// This state with one theme axis pinned differently.
    ///
    /// - Parameters:
    ///   - axis: The axis to pin.
    ///   - value: The value to pin it to, or `nil` to unpin it.
    /// - Returns: A copy.
    public func pinning(_ axis: String, to value: String?) -> ViewState {
        var copy = self
        copy.theme[axis] = value
        return copy
    }

    /// This state following someone else, or nobody.
    ///
    /// - Parameter follow: Who to follow.
    /// - Returns: A copy; the selection and the theme pins are kept, because a write
    ///   carries no theme and following one must never re-render the artboard under
    ///   different pins.
    public func following(_ follow: Follow) -> ViewState {
        var copy = self
        copy.follow = follow
        return copy
    }

    /// The query string, leading `?` included, or empty when nothing is set.
    ///
    /// The order is fixed — selection, theme, depth, follow, tab, language —
    /// so two URLs describing the same view are the same string, which is what makes a
    /// golden fixture and a browser's history both behave. A parameter at its default is
    /// left out, so the tab a selection implies is written and the tab it does not is
    /// silent.
    public var query: String {
        var parts: [String] = []
        if let node, !node.isEmpty {
            parts.append("node=\(ViewerLink.escape(node))")
        }
        if !theme.isEmpty {
            parts.append("theme=\(ViewerLink.escape(ThemeQuery.canonical(theme)))")
        }
        if let depth {
            parts.append("depth=\(depth)")
        }
        if let follow = follow.query {
            parts.append("follow=\(ViewerLink.escape(follow))")
        }
        // The tab is written whenever anything is selected, even when it is the one a
        // selection implies. Leaving it out would make the *Activity* tab's own link
        // `?node=…` with no tab — which parses straight back to Details, so the tab
        // would be unclickable. A link has to describe the view it opens.
        if tab != .fallback || node?.isEmpty == false {
            parts.append("tab=\(tab.rawValue)")
        }
        if let lang {
            parts.append("lang=\(lang.rawValue)")
        }
        return parts.isEmpty ? "" : "?" + parts.joined(separator: "&")
    }

    /// Just the theme, as a query — what an image URL carries and a selection does not.
    var themeQuery: String {
        theme.isEmpty ? "" : "?theme=\(ViewerLink.escape(ThemeQuery.canonical(theme)))"
    }

    /// The state a request describes.
    ///
    /// - Parameter request: The request to read.
    /// - Returns: The state its query names.
    /// - Throws: ``ViewerError/malformedTheme(_:)`` or
    ///   ``ViewerError/malformedNumber(parameter:value:)`` — a query that cannot be read
    ///   is an error naming the parameter, never a silently ignored one.
    public static func of(_ request: ViewerRequest) throws -> ViewState {
        try ViewState(
            node: request.http.query["node"].flatMap { $0.isEmpty ? nil : $0 },
            theme: request.theme(),
            depth: request.integer("depth"),
            follow: Follow.of(request.http.query["follow"]),
            tab: choice("tab", in: request, of: ViewerTab.self),
            lang: choice("lang", in: request, of: ViewerCodeTarget.self)
        )
    }

    /// Which panel a state with this selection opens on, when nothing says otherwise.
    ///
    /// One rule in one place, so a link the page wrote, a URL a person typed and the
    /// script's own reading of the query cannot disagree: selecting something means you
    /// want to look at it. An explicit `?tab=` always wins — until the next selection,
    /// which is the simple version of "unless the user picked a tab".
    ///
    /// - Parameter node: The selected node's address, or `nil`.
    /// - Returns: ``ViewerTab/details`` when something is selected, else
    ///   ``ViewerTab/fallback``.
    static func tab(forSelection node: String?) -> ViewerTab {
        (node?.isEmpty == false) ? .details : .fallback
    }

    /// One query parameter read as an enumerated choice.
    ///
    /// A value the enumeration does not have is a `400` naming it and listing what it
    /// could have been, never a silently ignored parameter: a `?tab=detials` that
    /// quietly showed Activity is how an agent loses an afternoon.
    ///
    /// - Parameters:
    ///   - name: The parameter's name.
    ///   - request: The request to read.
    ///   - type: The enumeration the value must belong to.
    /// - Returns: The choice, or `nil` when the query does not carry it.
    /// - Throws: ``ViewerError/malformedChoice(parameter:value:accepted:)``.
    static func choice<Choice: RawRepresentable & CaseIterable>(
        _ name: String,
        in request: ViewerRequest,
        of type: Choice.Type
    ) throws -> Choice? where Choice.RawValue == String {
        guard let raw = request.http.query[name], !raw.isEmpty else { return nil }
        guard let choice = type.init(rawValue: raw) else {
            throw ViewerError.malformedChoice(
                parameter: name, value: raw, accepted: type.allCases.map(\.rawValue)
            )
        }
        return choice
    }
}
