//
//  ArtboardMap.swift
//  WoodcaseViewer
//

import Elementary
import Foundation
import Woodcase

/// The bird's-eye view of a whole file: every artboard a real low-res render, placed at
/// the canvas position the file gives it, named underneath.
///
/// It is a **page**, not a band. A 150-point strip above the render made every box a
/// hairline on a wide file and taught you nothing a row of tabs had not; the arrangement
/// on the canvas is how the person who drew the file thinks about it, so that arrangement
/// is what you navigate by, at a size you can read. Clicking a box drills into that
/// artboard, and the artboard view then gets the whole pane.
///
/// Each box is an ordinary `<a>` wrapping an `<img>` from the PNG endpoint capped by
/// ``thumbnailEdge``, so the map works with the script switched off and the renders come
/// from the same warm cache the artboard view reads.
///
/// A box ships with its frame marked `is-loading`, which the stylesheet draws as a
/// shimmer *behind* the image: a render that has not landed yet reads as pending rather
/// than as an artboard with nothing in it. The image covers it when it paints, so the
/// page is right with the script off; `viewer.js` then drops the class so nothing
/// animates for the rest of the session.
///
/// It is also the fragment served at `GET /files/{file}/map`: an artboard added while
/// the map is open is a change to *this* element and nothing else on the page carries it.
///
/// ## Points in, pixels out
///
/// Every box is placed in **layout points** — `--v-board-x`, `--v-board-y`,
/// `--v-board-w`, `--v-board-h` — and the stylesheet multiplies each by one scale,
/// `--v-map-scale`, exactly as the render overlay multiplies its boxes by `--v-scale`.
/// The server writes a scale that fits an assumed pane; `viewer.js` overwrites it with
/// one measured against the real pane, and every box follows without being touched.
///
/// Labels are *not* multiplied: a name at 11px stays at 11px however far out the map is
/// zoomed, and it sits under the box rather than over the render, so a thumbnail is never
/// covered by its own name.
///
/// Artboards do not overlap — a root added without coordinates is placed clear of every
/// other root — so the map draws them where they are, with no packing fallback. An
/// overlapping file draws overlapping, which is the truth and is what `lint`'s
/// `artboard-overlap` finding is for.
public struct ArtboardMap: HTML {
    /// Creates a map.
    ///
    /// - Parameters:
    ///   - file: The file's id.
    ///   - artboards: Every artboard of the file, in document order.
    ///   - state: The current view state, which each box carries forward — minus the
    ///     selection, which belonged to the artboard it was made in.
    ///   - editors: For each artboard id, the identities that touched something inside it
    ///     inside the recency window, in the log's order of first appearance.
    public init(
        file: String,
        artboards: [Artboard],
        state: ViewState,
        editors: [String: [String]] = [:]
    ) {
        self.file = file
        self.artboards = artboards
        self.state = state
        self.editors = editors
    }

    /// The smallest zoom the map is ever drawn at.
    ///
    /// Below this the map stops shrinking and starts scrolling: a document spread over
    /// 40 000 points would otherwise squeeze every artboard into a hairline to fit a
    /// 760-point pane. The number is chosen so that a phone-width artboard — 400 points —
    /// is still 24 CSS pixels across, which is the narrowest box worth drawing at all.
    public static let minimumScale = 0.06

    /// The largest zoom the map is ever drawn at.
    ///
    /// A map is a map: a file with two small artboards is not blown up to fill the pane,
    /// because a half-size drawing of a whole document reads as an overview and a
    /// full-size one reads as a broken render.
    public static let maximumScale = 0.5

    /// The cap, in pixels, on a thumbnail's longer side.
    ///
    /// The render cache keys its images by this cap, so every box on the map shares one
    /// small render per artboard and theme rather than downsampling the 1600-pixel image
    /// the artboard view asks for. 320 is legible at the largest zoom this map draws
    /// (a 640-point artboard at 0.5) and cheap at the smallest.
    public static let thumbnailEdge = 320

    /// The pane width, in CSS pixels, the server assumes when it writes the first scale.
    ///
    /// The server cannot know the pane; it writes a scale for a typical one so the page
    /// is right before the script runs and does not visibly re-fit. `viewer.js` measures
    /// the real pane and overwrites it.
    static let assumedPaneWidth = 760.0

    /// The pane height, in CSS pixels, the server assumes.
    ///
    /// The map now fills the canvas pane rather than a fixed band, so this is a whole
    /// pane on a typical window rather than the stylesheet's own `height`.
    static let assumedPaneHeight = 560.0

    /// The file's id.
    public let file: String

    /// Every artboard of the file, in document order.
    public let artboards: [Artboard]

    /// The current view state.
    public let state: ViewState

    /// For each artboard id, the identities that touched something inside it recently.
    public let editors: [String: [String]]

    /// The canvas rectangle every artboard fits inside.
    ///
    /// Boxes are placed relative to its corner, not to the canvas origin: a file whose
    /// artboards all start at `x: 500` should draw against the left edge of its map, not
    /// 500 points of nothing.
    ///
    /// - Returns: The union of the artboards' rects, or a zero rect for no artboards.
    public var extent: PenRect {
        guard let first = artboards.first else {
            return PenRect(x: 0, y: 0, width: 0, height: 0)
        }
        var minX = first.x, minY = first.y
        var maxX = first.x + first.width, maxY = first.y + first.height
        for board in artboards.dropFirst() {
            minX = min(minX, board.x)
            minY = min(minY, board.y)
            maxX = max(maxX, board.x + board.width)
            maxY = max(maxY, board.y + board.height)
        }
        return PenRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// The zoom the server ships, fitting ``extent`` into an assumed pane.
    public var scale: Double {
        Self.scale(
            mapWidth: extent.width,
            mapHeight: extent.height,
            paneWidth: Self.assumedPaneWidth,
            paneHeight: Self.assumedPaneHeight
        )
    }

    /// The zoom that fits a map of a given size into a pane.
    ///
    /// The same arithmetic `viewer.js` runs against the measured pane, kept here so the
    /// server's first paint and the script's re-fit are one rule with one pair of bounds.
    ///
    /// - Parameters:
    ///   - mapWidth: The map's width in layout points.
    ///   - mapHeight: Its height in layout points.
    ///   - paneWidth: The available width in CSS pixels.
    ///   - paneHeight: The available height in CSS pixels.
    /// - Returns: CSS pixels per layout point, between ``minimumScale`` and
    ///   ``maximumScale``.
    public static func scale(
        mapWidth: Double,
        mapHeight: Double,
        paneWidth: Double,
        paneHeight: Double
    ) -> Double {
        guard mapWidth > 0, mapHeight > 0 else { return maximumScale }
        let fit = min(paneWidth / mapWidth, paneHeight / mapHeight)
        return min(maximumScale, max(minimumScale, fit))
    }

    /// The CSS custom properties that place one box, in layout points.
    ///
    /// - Parameters:
    ///   - board: The artboard to place.
    ///   - extent: The map's own rectangle, whose corner the box is measured from.
    /// - Returns: A `style` value the stylesheet multiplies by `--v-map-scale`.
    static func placement(_ board: Artboard, in extent: PenRect) -> String {
        "--v-board-x: \(OutlineRow.number(board.x - extent.x)); "
            + "--v-board-y: \(OutlineRow.number(board.y - extent.y)); "
            + "--v-board-w: \(OutlineRow.number(board.width)); "
            + "--v-board-h: \(OutlineRow.number(board.height))"
    }

    /// A zoom as CSS writes it — three decimals, which is finer than a pixel at any map
    /// size the minimum zoom allows.
    ///
    /// - Parameter value: The zoom.
    /// - Returns: Its text.
    static func zoom(_ value: Double) -> String {
        String(format: "%.3f", value)
    }

    /// The plane's size and zoom, written on the scroll container.
    var mapStyle: String {
        let box = extent
        return "--v-map-scale: \(Self.zoom(scale)); "
            + "--v-map-w: \(OutlineRow.number(box.width)); "
            + "--v-map-h: \(OutlineRow.number(box.height))"
    }

    /// The state a box's link carries: this one, minus the selection.
    var linkState: ViewState {
        state.selecting(nil)
    }

    public var body: some HTML {
        let box = extent
        div(
            .class("v-map"),
            .id(ViewerLink.Fragment.map.target),
            .data("file", value: file),
            .style(mapStyle)
        ) {
            div(.class("v-map-plane")) {
                for board in artboards {
                    Board(
                        file: file,
                        board: board,
                        extent: box,
                        state: linkState,
                        editors: editors[board.id] ?? []
                    )
                }
            }
        }
    }

    /// One artboard's box: the thumbnail, and its name underneath.
    struct Board: HTML {
        /// The file's id.
        let file: String

        /// The artboard this box draws.
        let board: Artboard

        /// The map's own rectangle, whose corner this box is measured from.
        let extent: PenRect

        /// The state the link carries, selection already dropped.
        let state: ViewState

        /// Who touched something inside this artboard recently.
        let editors: [String]

        /// The colour of the recently-edited outline: the first editor's, matching the
        /// bar an outline row grows for the same reason.
        var editorColor: String {
            ActorColor(name: editors.first ?? "").css
        }

        var body: some HTML {
            a(
                .class("v-map-board"),
                .data("artboard", value: board.id),
                .title(board.name ?? board.id),
                .style(ArtboardMap.placement(board, in: extent)),
                .href(ViewerLink.artboard(file: file, artboard: board.id, state: state))
            ) {
                // `is-loading` is the shimmer, and it ships on: the image behind it is
                // the thing that has not arrived. It sits on the frame rather than on
                // the box, which already carries `is-touched` and means something else.
                span(.class("v-map-frame is-loading")) {
                    img(
                        .class("v-map-thumb"),
                        .src(ViewerLink.png(
                            file: file,
                            artboard: board.id,
                            maxEdge: ArtboardMap.thumbnailEdge,
                            state: state
                        )),
                        // Decorative: the name is beside it in the label, and a screen
                        // reader repeating it would read every artboard twice.
                        .alt(""),
                        .width(Int(board.width.rounded())),
                        .height(Int(board.height.rounded())),
                        .custom(name: "loading", value: "lazy"),
                        .custom(name: "decoding", value: "async")
                    )
                }
                span(.class("v-map-label")) {
                    KindMark(
                        isReusable: board.isReusable,
                        isInstance: board.isInstance,
                        isSlot: board.isSlot
                    )
                    span(.class("v-map-name")) { board.name ?? board.id }
                }
            }
            // Elementary merges a second `style` onto the first, so this adds the actor
            // colour to the placement above rather than replacing it.
            .attributes(
                .class("is-touched"),
                .style("--v-actor: \(editorColor)"),
                .data("editors", value: editors.joined(separator: " ")),
                when: !editors.isEmpty
            )
        }
    }
}
