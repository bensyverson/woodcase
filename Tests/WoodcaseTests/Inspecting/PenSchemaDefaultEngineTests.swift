//
//  PenSchemaDefaultEngineTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Holds every default the schema lists (``PenSchemaTable/Property/default``) to what the
/// layout engine and the renderer actually do with the property unset.
///
/// Each pin lays out and draws a small document three times: with the property unset,
/// with it set to the schema's default, and with it set to another value. The first two
/// must match rect for rect and pixel for pixel, or the schema names a default the engine
/// does not use; the third must differ, or the fixture does not exercise the property and
/// the match proves nothing. A default the schema gains without a pin here fails
/// ``everyLiteralDefaultIsPinned()``.
struct PenSchemaDefaultEngineTests {
    // MARK: - Fixtures

    /// A gray backdrop under every fixture, so a blend mode has something to blend onto.
    private static let backdrop: AnyCodable = [
        "type": "rectangle", "id": "bg", "x": 0, "y": 0, "width": 400, "height": 300, "fill": "#808080",
    ]

    /// Wraps the node under test in a document over the backdrop.
    private static func document(_ node: AnyCodable) -> AnyCodable {
        ["children": [backdrop, node]]
    }

    private static let rectangle = document([
        "type": "rectangle", "id": "t", "x": 20, "y": 20, "width": 100, "height": 60,
        "fill": "#3366FF", "stroke": "#FF0000", "strokeWidth": 8,
    ])

    /// The rectangle with a dash, so the dash's offset has something to move.
    private static let dashedRectangle = document([
        "type": "rectangle", "id": "t", "x": 20, "y": 20, "width": 100, "height": 60,
        "fill": "#3366FF", "stroke": "#FF0000", "strokeWidth": 8,
        "metadata": ["type": "woodcase", "woodcase": ["strokeDash": [20, 10]]],
    ])

    /// A fixed frame holding a short child and one that overflows it.
    private static let frame = document([
        "type": "frame", "id": "t", "x": 20, "y": 20, "width": 160, "height": 120, "fill": "#FFFFFF",
        "children": [
            ["type": "rectangle", "id": "a", "width": 30, "height": 30, "fill": "#0000FF"],
            ["type": "rectangle", "id": "b", "width": 20, "height": 150, "fill": "#00AA00"],
        ],
    ])

    private static let text = document([
        "type": "text", "id": "t", "x": 20, "y": 20, "width": 200, "height": 80,
        "textGrowth": "fixed-width-height", "content": "Hello Wg", "fill": "#000000",
    ])

    /// A text with no box of its own, sized by its words.
    private static let growingText = document([
        "type": "text", "id": "t", "x": 20, "y": 20, "content": "Hello Wg", "fill": "#000000",
    ])

    private static let note = document(["type": "note", "id": "t", "x": 20, "y": 20, "content": "Hello note text"])

    private static let prompt = document(["type": "prompt", "id": "t", "x": 20, "y": 20, "content": "Do it"])

    private static let ellipse = document([
        "type": "ellipse", "id": "t", "x": 20, "y": 20, "width": 100, "height": 100,
        "fill": "#3366FF", "sweepAngle": 180,
    ])

    private static let polygon = document([
        "type": "polygon", "id": "t", "x": 20, "y": 20, "width": 100, "height": 100, "fill": "#3366FF",
    ])

    /// Two nested squares wound the same way: nonzero fills the hole, evenodd leaves it.
    private static let path = document([
        "type": "path", "id": "t", "x": 20, "y": 20, "width": 100, "height": 100, "fill": "#3366FF",
        "geometry": "M0 0 L100 0 L100 100 L0 100 Z M25 25 L75 25 L75 75 L25 75 Z",
    ])

    private static let line = document([
        "type": "line", "id": "t", "x": 20, "y": 50, "width": 200, "height": 0,
        "stroke": "#FF0000", "strokeWidth": 10,
    ])

    // MARK: - Pins

    /// One default held to the engine.
    struct Pin: CustomTestStringConvertible {
        /// The schema table the default is read from.
        let type: PenNode.NodeType
        /// The property path.
        let path: String
        /// The document drawn.
        let fixture: AnyCodable
        /// The id of the node the property is written on.
        var target = "t"
        /// A value that must draw differently from the default.
        let alternative: AnyCodable

        var testDescription: String {
            "\(type.rawValue) \(path)"
        }
    }

    static let pins: [Pin] = [
        // Placement and appearance, on every node.
        Pin(type: .rectangle, path: "common.x", fixture: rectangle, alternative: 40),
        Pin(type: .rectangle, path: "common.y", fixture: rectangle, alternative: 40),
        Pin(type: .rectangle, path: "common.rotation", fixture: rectangle, alternative: 30),
        Pin(type: .rectangle, path: "common.opacity", fixture: rectangle, alternative: 0.5),
        Pin(type: .rectangle, path: "common.enabled", fixture: rectangle, alternative: false),
        Pin(type: .frame, path: "common.flipX", fixture: frame, alternative: true),
        Pin(type: .frame, path: "common.flipY", fixture: frame, alternative: true),
        Pin(type: .frame, path: "common.layoutPosition", fixture: frame, target: "a", alternative: "absolute"),
        // Layout.
        Pin(type: .frame, path: "kind.layout", fixture: frame, alternative: "vertical"),
        Pin(type: .frame, path: "kind.gap", fixture: frame, alternative: 10),
        Pin(type: .frame, path: "kind.padding", fixture: frame, alternative: 10),
        Pin(type: .frame, path: "kind.justifyContent", fixture: frame, alternative: "end"),
        Pin(type: .frame, path: "kind.alignItems", fixture: frame, alternative: "end"),
        Pin(type: .frame, path: "kind.clip", fixture: frame, alternative: true),
        Pin(type: .frame, path: "kind.width", fixture: frame, alternative: 100),
        Pin(type: .frame, path: "kind.height", fixture: frame, alternative: 50),
        // Shape and stroke.
        Pin(type: .rectangle, path: "kind.cornerRadius", fixture: rectangle, alternative: 20),
        Pin(type: .rectangle, path: "kind.strokeWidth", fixture: rectangle, alternative: 2),
        Pin(type: .rectangle, path: "kind.strokeAlignment", fixture: rectangle, alternative: "inner"),
        Pin(type: .rectangle, path: "kind.strokeLinejoin", fixture: rectangle, alternative: "round"),
        Pin(type: .rectangle, path: "kind.blendMode", fixture: rectangle, alternative: "multiply"),
        Pin(type: .rectangle, path: "kind.strokeDash", fixture: rectangle, alternative: [8, 4]),
        Pin(type: .rectangle, path: "kind.strokeDashOffset", fixture: dashedRectangle, alternative: 5),
        // A right angle's miter reaches √2 stroke widths: Pen's 4 keeps it, 1 bevels it.
        Pin(type: .rectangle, path: "kind.strokeMiterLimit", fixture: rectangle, alternative: 1),
        Pin(type: .line, path: "kind.strokeLinecap", fixture: line, alternative: "round"),
        Pin(type: .ellipse, path: "kind.innerRadius", fixture: ellipse, alternative: 0.5),
        Pin(type: .ellipse, path: "kind.startAngle", fixture: ellipse, alternative: 90),
        Pin(type: .ellipse, path: "kind.sweepAngle", fixture: ellipse, alternative: 90),
        Pin(type: .polygon, path: "kind.polygonCount", fixture: polygon, alternative: 3),
        Pin(type: .path, path: "kind.fillRule", fixture: path, alternative: "evenodd"),
        // Text.
        Pin(type: .text, path: "kind.textGrowth", fixture: growingText, alternative: "fixed-width"),
        Pin(type: .text, path: "kind.fontFamily", fixture: text, alternative: "Courier"),
        Pin(type: .text, path: "kind.fontSize", fixture: text, alternative: 24),
        Pin(type: .text, path: "kind.fontWeight", fixture: text, alternative: "700"),
        Pin(type: .text, path: "kind.fontStyle", fixture: text, alternative: "italic"),
        Pin(type: .text, path: "kind.textAlign", fixture: text, alternative: "right"),
        Pin(type: .text, path: "kind.textAlignVertical", fixture: text, alternative: "bottom"),
        Pin(type: .text, path: "kind.underline", fixture: text, alternative: true),
        Pin(type: .text, path: "kind.strikethrough", fixture: text, alternative: true),
        // Notes and cards.
        Pin(type: .note, path: "kind.fontSize", fixture: note, alternative: 20),
        Pin(type: .note, path: "kind.lineHeight", fixture: note, alternative: 2),
        Pin(type: .note, path: "kind.width", fixture: note, alternative: 300),
        Pin(type: .note, path: "kind.height", fixture: note, alternative: 280),
        Pin(type: .prompt, path: "kind.width", fixture: prompt, alternative: 380),
        Pin(type: .prompt, path: "kind.height", fixture: prompt, alternative: 280),
    ]

    @Test("Leaving a property unset draws exactly as writing its default", arguments: pins)
    func unsetDrawsAsDefault(pin: Pin) throws {
        let property = try #require(PenSchema.field(pin.path, for: pin.type))
        let key = try #require(property.key.written)
        let value = try #require(property.default?.value, "the schema lists no literal default")

        let unset = try Self.draw(pin.fixture.setting(key, to: nil, on: pin.target))
        let asDefault = try Self.draw(pin.fixture.setting(key, to: value, on: pin.target))
        let other = try Self.draw(pin.fixture.setting(key, to: pin.alternative, on: pin.target))

        #expect(unset == asDefault, "the engine does not draw an unset \(pin.path) as \(value)")
        #expect(unset != other, "the fixture does not exercise \(pin.path)")
    }

    /// Editor state the schema lists with a default but the engine never draws: a lock and
    /// the default-text-style mark (natural paths since leaf 9Sw8C0, so now in the tables).
    private static let undrawn: Set<String> = ["common.locked", "kind.defaultTextStyle"]

    @Test("Every literal default the schema lists is pinned to the engine")
    func everyLiteralDefaultIsPinned() {
        let pinned = Set(Self.pins.compactMap { pin in
            PenSchema.field(pin.path, for: pin.type)?.default.map { Listed(path: pin.path, default: $0) }
        })
        #expect(pinned.count == Self.pins.count, "a pin names a property with no literal default")
        for type in PenNode.NodeType.allCases {
            for property in PenSchema.fields(for: type) where !Self.undrawn.contains(property.path) {
                guard let listed = property.default, listed.value != nil else { continue }
                #expect(
                    pinned.contains(Listed(path: property.path, default: listed)),
                    "\(type.rawValue) \(property.path) = \(listed) has no pin"
                )
            }
        }
    }

    @Test("A text's line height and letter spacing, unset, are the font's own")
    func derivedDefaultsAreTheFonts() throws {
        let style = PenTextStyle(PenNode.TextData())
        #expect(style.lineHeight == nil)
        #expect(style.letterSpacing == nil)
        let derived = Set(PenNode.NodeType.allCases.flatMap { type in
            PenSchema.fields(for: type).compactMap { property -> String? in
                guard case .derived? = property.default else { return nil }
                return "\(type.rawValue) \(property.path)"
            }
        })
        #expect(derived == ["text kind.lineHeight", "text kind.letterSpacing",
                            "note kind.letterSpacing", "prompt kind.letterSpacing", "context kind.letterSpacing"])
        let note = try #require(PenParser.parse(#"{"children":[{"type":"note","id":"n","content":"x"}]}"#)
            .children.first?.noteTextStyle)
        #expect(note.letterSpacing == nil)
    }

    // MARK: - Drawing

    /// A default as listed, for the coverage check.
    private struct Listed: Hashable {
        let path: String
        let `default`: PenPropertyDefault
    }

    /// What the engine makes of a document: every node's rect, and the pixels drawn.
    private struct Drawing: Equatable {
        let rects: [String: PenRect]
        let pixels: Data
    }

    private static func draw(_ fixture: AnyCodable) throws -> Drawing {
        let json = try String(decoding: JSONEncoder().encode(fixture), as: UTF8.self)
        let document = try PenParser.parse(json)
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(document, layoutRects: rects, size: CGSize(width: 400, height: 300)))
        let pixels = try #require(image.dataProvider?.data as Data?)
        return Drawing(rects: rects, pixels: pixels)
    }
}

private extension AnyCodable {
    /// The document with one key of the node `id` set, or removed for `nil`.
    ///
    /// A dotted key — `metadata.woodcase.blendMode`, where the file stores a natural path —
    /// is set inside the objects it names.
    func setting(_ key: String, to value: AnyCodable?, on id: String) -> AnyCodable {
        switch self {
        case let .dictionary(entries):
            if entries["id"] == .string(id) {
                return setting(keyPath: key.split(separator: ".").map(String.init), to: value)
            }
            var entries = entries
            if let children = entries["children"] {
                entries["children"] = children.setting(key, to: value, on: id)
            }
            return .dictionary(entries)
        case let .array(items):
            return .array(items.map { $0.setting(key, to: value, on: id) })
        default:
            return self
        }
    }

    /// This object with the value at `keyPath` set, or removed for `nil`.
    private func setting(keyPath: [String], to value: AnyCodable?) -> AnyCodable {
        guard let head = keyPath.first else { return value ?? .null }
        var entries: [String: AnyCodable] = if case let .dictionary(existing) = self { existing } else { [:] }
        if keyPath.count == 1 {
            if let value { entries[head] = value } else { entries.removeValue(forKey: head) }
        } else {
            entries[head] = (entries[head] ?? .dictionary([:])).setting(keyPath: Array(keyPath.dropFirst()), to: value)
        }
        return .dictionary(entries)
    }
}
