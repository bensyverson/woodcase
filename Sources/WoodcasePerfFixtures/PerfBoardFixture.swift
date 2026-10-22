//
//  PerfBoardFixture.swift
//  WoodcasePerfFixtures
//

import Foundation
import Woodcase

/// One artboard of Penumbra's perf board (Penumbra `scripts/perf-board`), rebuilt here so
/// Woodcase's tests need no file from Penumbra: a free-placement 1200×1000 frame holding a
/// header stack (a logo, a title and four nav texts) and twenty clipping cards in a 5×4
/// grid, each a vertical stack of a photo and a content stack — a title, a wrapping body,
/// an avatar row, three tags and a button. 308 nodes, 165 of them texts; the image fills
/// are left out, since they change no extent.
public enum PerfBoardFixture {
    /// How many nodes the artboard holds.
    public static let nodeCount = 308

    /// How many texts it holds.
    public static let textCount = 165

    /// The text inks a call to `paintedExtent` per node asks for: each text once for
    /// itself and once for every unclipped ancestor below its card or up to the artboard —
    /// 22 per card and 3 per header text.
    public static let perNodeInkLookups = 455

    /// The palette the cards' accents cycle through.
    private static let palette = ["#4F46E5", "#0EA5E9", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6", "#EC4899", "#14B8A6"]

    /// The words the texts are made of.
    private static let words = ("layout render frame stack token color grid panel board cursor anchor shadow "
        + "stroke radius label badge avatar canvas spacing outline").split(separator: " ").map(String.init)

    /// The artboard, parsed.
    public static func document() throws -> PenDocument {
        var builder = Builder()
        let root: [String: Any] = ["version": "2.20", "children": [builder.artboard()]]
        return try PenParser.parse(JSONSerialization.data(withJSONObject: root))
    }

    /// Numbers the nodes as the script does, so ids are unique.
    private struct Builder {
        var count = 0

        mutating func node(_ type: String, _ prefix: String, _ fields: [String: Any] = [:]) -> [String: Any] {
            count += 1
            return fields.merging(["type": type, "id": "\(prefix)-\(count)"]) { $1 }
        }

        mutating func text(
            _ prefix: String, _ content: String, _ size: Double, _ color: String,
            weight: String = "400", wraps: Bool = false
        ) -> [String: Any] {
            var fields: [String: Any] = [
                "content": content, "fontFamily": "Helvetica", "fontSize": size, "fontWeight": weight, "fill": color,
            ]
            if wraps {
                fields["width"] = "fill_container"
                fields["textGrowth"] = "fixed-width"
            }
            return node("text", prefix, fields)
        }

        mutating func frame(
            _ prefix: String, _ layout: String, _ children: [[String: Any]], _ fields: [String: Any] = [:]
        ) -> [String: Any] {
            node("frame", prefix, fields.merging(["layout": layout, "children": children]) { $1 })
        }

        mutating func header() -> [String: Any] {
            let logo = node("rectangle", "logo", ["width": 40, "height": 40, "cornerRadius": 8, "fill": palette[0]])
            let title = text("title", "Artboard 1", 22, "#111827", weight: "600")
            let nav = words[0 ..< 4].map { text("nav", $0.capitalized, 14, "#374151") }
            return frame("header", "horizontal", [logo, title] + nav, [
                "x": 0, "y": 0, "width": 1200, "height": 80, "gap": 24, "padding": 20,
                "alignItems": "center", "fill": "#FFFFFF",
            ])
        }

        mutating func card(column: Int, row: Int) -> [String: Any] {
            let n = row * 5 + column
            let accent = palette[n % palette.count]
            let cardWords = (0 ..< 12).map { words[(n + $0) % words.count] }
            let avatarRow = frame("avatar-row", "horizontal", [
                node("ellipse", "avatar", ["width": 16, "height": 16, "fill": accent]),
                text("author", cardWords[1].capitalized, 10, "#374151"),
                text("date", "Oct \(n % 28 + 1)", 10, "#9CA3AF"),
            ], ["gap": 6, "alignItems": "center"])
            let tags = frame("tags", "horizontal", cardWords[2 ..< 5].map { text("tag", "#\($0)", 10, accent) }, ["gap": 6])
            let button = frame("button", "horizontal", [text("button-label", "Open", 11, "#FFFFFF", weight: "500")], [
                "padding": [4, 10], "cornerRadius": 6, "fill": accent,
            ])
            let content = frame("content", "vertical", [
                text("card-title", "Card \(n + 1): \(cardWords[0].capitalized)", 13, "#111827", weight: "600"),
                text("body", cardWords.joined(separator: " "), 11, "#4B5563", wraps: true),
                avatarRow, tags, button,
            ], ["width": "fill_container", "gap": 6, "padding": 10])
            let photo = node("rectangle", "photo", ["width": "fill_container", "height": 70, "fill": "#CBD5E1"])
            return frame("card", "vertical", [photo, content], [
                "x": 40 + column * 228, "y": 120 + row * 220, "width": 208, "height": 210, "cornerRadius": 10,
                "clip": true, "fill": "#FFFFFF", "stroke": "#E5E7EB", "strokeWidth": 1,
            ])
        }

        mutating func artboard() -> [String: Any] {
            let header = header()
            var cards: [[String: Any]] = []
            for row in 0 ..< 4 {
                for column in 0 ..< 5 {
                    cards.append(card(column: column, row: row))
                }
            }
            return frame("artboard", "none", [header] + cards, [
                "x": 0, "y": 0, "width": 1200, "height": 1000, "fill": "#F3F4F6",
            ])
        }
    }
}
