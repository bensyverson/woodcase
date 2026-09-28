//
//  ViewerLink.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Every URL the page writes, in one place.
///
/// Not a convenience: an artboard id can contain a slash — a top-level component
/// instance expands to `YGJ0d/nSNTs` — and a link that fails to encode it 404s against a
/// server that decodes path segments one at a time. Building URLs by interpolation is
/// how that bug gets written once per component, so no component interpolates one.
///
/// ```swift
/// ViewerLink.artboard(file: "a1b2c3", artboard: "YGJ0d/nSNTs", state: state)
/// // "/files/a1b2c3/artboards/YGJ0d%2FnSNTs?node=Ttl01"
/// ```
public enum ViewerLink {
    /// The fragments the page re-requests when something changes.
    ///
    /// Each is the same component the full page rendered, served on its own, so a live
    /// update is a server render swapped into place and never a second implementation.
    public enum Fragment: String, Friendly, CaseIterable {
        /// The outline panel's rows. It names an artboard — every row's link opens the
        /// node *in the artboard you are looking at* — so it is reached through
        /// ``ViewerLink/outline(file:artboard:state:)``.
        case outline
        /// The activity feed.
        case activity
        /// The variables section.
        case variables
        /// The selected node's attributes and where each of them came from. Like the
        /// outline it is a whole-file fragment: which node it describes rides in
        /// `?node=`, so it needs no artboard in its path.
        case details
        /// The presence stack in the top bar.
        case presence
        /// The Follow control in the top bar. Its own fragment because it changes
        /// without the file changing: manual navigation drops follow, and the dropdown
        /// that says so is server-rendered rather than edited in JavaScript. It is
        /// reached through ``ViewerLink/follow(file:artboard:state:)``, whose artboard is
        /// the page the form submits back to — `nil` on the map page, which has none.
        case follow
        /// The bird's-eye map that *is* the map page's canvas — the map a new artboard
        /// has to join without a reload. Whole-file: nothing is current on the map, so it
        /// needs no artboard in its path.
        case map
        /// The map page's outline: one row per artboard rather than one per node. It
        /// replaces the node outline while the map is showing, so it answers with the
        /// same element id and swaps into the same slot.
        case artboards
        /// The render, its overlay and the selection footer — everything that moves when
        /// the file changes or the selection does. It needs an artboard, so it is reached
        /// through ``ViewerLink/render(file:artboard:state:)`` rather than
        /// ``ViewerLink/fragment(_:file:state:)``.
        case render
        /// The generated code beside the render. It names an artboard — the code is
        /// *this* artboard's file — so it is reached through
        /// ``ViewerLink/code(file:artboard:state:)``.
        case code

        /// The element id the fragment replaces, which is also the swap target the
        /// script looks for.
        ///
        /// The fragment's response *is* that element, so the script replaces it whole
        /// rather than setting `innerHTML` — an element that carries state in its own
        /// attributes (the stage's scale, a panel's id) must be replaced by the element
        /// the server rendered, not filled with its contents.
        ///
        /// Two fragments answer with an id that is not their own name: ``render`` is the
        /// region rather than the image, and ``artboards`` is the *outline* — the map
        /// page's outline lists artboards instead of nodes, and it takes the outline's
        /// place rather than sitting beside it.
        public var target: String {
            switch self {
            case .render: "v-render-region"
            case .artboards: "v-outline"
            default: "v-\(rawValue)"
            }
        }
    }

    /// The dashboard.
    public static let dashboard = "/"

    /// The stylesheet.
    public static let stylesheet = "/viewer.css"

    /// The script.
    public static let script = "/viewer.js"

    /// The event stream.
    public static let events = "/events"

    /// The preview catalog's index: every component that declares states.
    public static let previews = "/preview"

    /// One component's canvas: every state it declares, stacked.
    ///
    /// - Parameter component: The component's slug.
    /// - Returns: The path.
    public static func previewComponent(_ component: String) -> String {
        "\(previews)/\(escape(component))"
    }

    /// One state on a page of its own — the URL a review shot opens.
    ///
    /// - Parameters:
    ///   - component: The component's slug.
    ///   - state: The state's slug within it.
    /// - Returns: The path.
    public static func previewState(component: String, state: String) -> String {
        "\(previewComponent(component))/\(escape(state))"
    }

    /// One file's page.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - state: The view state to carry.
    /// - Returns: The path with its query.
    public static func file(_ file: String, state: ViewState = ViewState()) -> String {
        "/files/\(escape(file))\(state.query)"
    }

    /// One artboard's page.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard's node id, slash and all.
    ///   - state: The view state to carry.
    /// - Returns: The path with its query.
    public static func artboard(file: String, artboard: String, state: ViewState = ViewState()) -> String {
        "/files/\(escape(file))/artboards/\(escape(artboard))\(state.query)"
    }

    /// One artboard's rendered image.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard's node id.
    ///   - maxEdge: A cap on the longer side in pixels, or `nil` for the render cache's
    ///     own default. The map's thumbnails ask for a small one; the artboard view asks
    ///     for none, because it is the render.
    ///   - state: The view state; only its theme reaches the renderer.
    /// - Returns: The path with its query.
    public static func png(
        file: String,
        artboard: String,
        maxEdge: Int? = nil,
        state: ViewState = ViewState()
    ) -> String {
        var parts: [String] = []
        if let maxEdge {
            parts.append("max=\(maxEdge)")
        }
        if !state.theme.isEmpty {
            parts.append("theme=\(escape(ThemeQuery.canonical(state.theme)))")
        }
        let query = parts.isEmpty ? "" : "?" + parts.joined(separator: "&")
        return "/files/\(escape(file))/artboards/\(escape(artboard)).png\(query)"
    }

    /// One file's settled tree, as JSON.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - state: The view state to carry.
    /// - Returns: The path with its query.
    public static func tree(file: String, state: ViewState = ViewState()) -> String {
        "/files/\(escape(file))/tree.json\(state.query)"
    }

    /// A page fragment.
    ///
    /// - Parameters:
    ///   - fragment: Which fragment.
    ///   - file: The file's id.
    ///   - state: The view state the fragment must render under.
    /// - Returns: The path with its query.
    public static func fragment(_ fragment: Fragment, file: String, state: ViewState = ViewState()) -> String {
        "/files/\(escape(file))/\(fragment.rawValue)\(state.query)"
    }

    /// The outline fragment: one row per node, each linking into the artboard on screen.
    ///
    /// It names an artboard even though the tree is the whole file's, because a row's
    /// `href` has to say *where* to select the node: `/files/{file}?node=…` is the map
    /// now, so a row that wrote it would navigate out of the artboard it was clicked in.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard the rows select into.
    ///   - state: The view state the fragment must render under.
    /// - Returns: The path with its query.
    public static func outline(file: String, artboard: String, state: ViewState = ViewState()) -> String {
        "/files/\(escape(file))/artboards/\(escape(artboard))/outline\(state.query)"
    }

    /// The Follow control fragment: the dropdown and, when follow is paused, the
    /// link that resumes it.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard's node id — the page the control's form submits to —
    ///     or `nil` on the map page, whose form submits to the map.
    ///   - state: The view state the fragment must render under.
    /// - Returns: The path with its query.
    public static func follow(
        file: String,
        artboard: String? = nil,
        state: ViewState = ViewState()
    ) -> String {
        guard let artboard else {
            return "/files/\(escape(file))/follow\(state.query)"
        }
        return "/files/\(escape(file))/artboards/\(escape(artboard))/follow\(state.query)"
    }

    /// The render fragment: the image, its overlay and the selection footer.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard's node id.
    ///   - state: The view state the fragment must render under.
    /// - Returns: The path with its query.
    public static func render(file: String, artboard: String, state: ViewState = ViewState()) -> String {
        "/files/\(escape(file))/artboards/\(escape(artboard))/render\(state.query)"
    }

    /// The code fragment: one generated file for this artboard, with its language picker.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard's node id.
    ///   - state: The view state; its `lang` chooses which generated file.
    /// - Returns: The path with its query.
    public static func code(file: String, artboard: String, state: ViewState = ViewState()) -> String {
        "/files/\(escape(file))/artboards/\(escape(artboard))/code\(state.query)"
    }

    /// One artboard as a downloadable file.
    ///
    /// The size parameters are separate rather than one, because they answer different
    /// questions and both get asked: `scale` is "twice the design", `max` is "no longer
    /// than this on its longer side, in points". `max` wins when both are given.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboard: The artboard's node id.
    ///   - format: What to write.
    ///   - scale: Pixels per layout point, for a raster format.
    ///   - maxEdge: A cap on the longer side in points, for a raster format.
    ///   - state: The view state; only its theme reaches the renderer.
    /// - Returns: The path with its query.
    public static func export(
        file: String,
        artboard: String,
        format: ViewerExportFormat,
        scale: Int? = nil,
        maxEdge: Int? = nil,
        state: ViewState = ViewState()
    ) -> String {
        var parts = ["format=\(escape(format.query))"]
        if let scale {
            parts.append("scale=\(scale)")
        }
        if let maxEdge {
            parts.append("max=\(maxEdge)")
        }
        if !state.theme.isEmpty {
            parts.append("theme=\(escape(ThemeQuery.canonical(state.theme)))")
        }
        return "/files/\(escape(file))/artboards/\(escape(artboard))/export?"
            + parts.joined(separator: "&")
    }

    /// Percent-encodes one path segment or query value.
    ///
    /// Everything outside the unreserved set goes, which is stricter than either
    /// position needs and is the point: one escaping rule, no place where a slash, a
    /// colon or an ampersand can arrive unencoded.
    ///
    /// - Parameter text: The text to encode.
    /// - Returns: The encoded text.
    static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? text
    }

    /// RFC 3986's unreserved set.
    private static let unreserved: CharacterSet = {
        var set = CharacterSet.alphanumerics
        set.insert(charactersIn: "-._~")
        return set
    }()
}
