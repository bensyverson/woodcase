//
//  PenNestedDefaultEngineTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// Holds every default a nested key lists (``PenNestedShape/Field/default``) to what the
/// renderer actually does with the key unset.
///
/// The nested twin of ``PenSchemaDefaultEngineTests``: each pin draws a small document
/// three times, with the key unset, with it set to the schema's default, and with it set
/// to another value. The first two must match pixel for pixel, or the schema names a
/// default the renderer does not use; the third must differ, or the fixture does not
/// exercise the key. A nested default the schema gains without a pin here fails
/// ``everyNestedDefaultIsPinned()``.
struct PenNestedDefaultEngineTests {
    // MARK: - Fixtures

    /// Black and white stripes under every fixture, so a blend mode, a backdrop blur and a
    /// shadow each have something to act on.
    private static let backdrop: [AnyCodable] = [
        ["type": "rectangle", "id": "bg", "x": 0, "y": 0, "width": 400, "height": 300, "fill": "#808080"],
        ["type": "rectangle", "id": "s1", "x": 10, "y": 0, "width": 20, "height": 300, "fill": "#000000"],
        ["type": "rectangle", "id": "s2", "x": 50, "y": 0, "width": 20, "height": 300, "fill": "#FFFFFF"],
        ["type": "rectangle", "id": "s3", "x": 90, "y": 0, "width": 20, "height": 300, "fill": "#000000"],
    ]

    /// A node over the stripes, with `key` set to `value`.
    private static func document(_ key: String, _ value: AnyCodable, stroked: Bool = false) -> AnyCodable {
        var node: [String: AnyCodable] = [
            "type": "rectangle", "id": "t", "x": 20, "y": 20, "width": 100, "height": 60,
        ]
        node[key] = value
        // Translucent, so a backdrop blur under the node shows through it.
        if key != "fill" { node["fill"] = "#3366FF99" }
        if stroked { node["stroke"] = "#FF0000" }
        return ["version": "2.20", "children": .array(backdrop + [.dictionary(node)])]
    }

    /// A linear gradient, turned so that its center shows on a box that is wider than it
    /// is tall; `radial` where the size, which a linear ramp does not read along x, must show.
    private static func gradient(_ extra: [String: AnyCodable] = ["rotation": 30], type: String = "linear") -> AnyCodable {
        var fill: [String: AnyCodable] = [
            "type": "gradient", "gradientType": .string(type),
            "colors": [["color": "#FF0000", "position": 0], ["color": "#0000FF", "position": 1]],
        ]
        for (key, value) in extra {
            fill[key] = value
        }
        return .dictionary(fill)
    }

    private static let mesh: AnyCodable = [
        "type": "mesh_gradient", "columns": 2, "rows": 2,
        "colors": ["#FF0000", "#00FF00", "#0000FF", "#FFFFFF"],
        "points": [[0, 0], [1, 0], [0, 1], [1, 1]],
    ]

    private static let image: AnyCodable = ["type": "image", "url": "magenta", "mode": "fill"]

    private static let color: AnyCodable = ["type": "color", "color": "#33CC66"]

    /// A shadow with every optional key written, so a pin can remove the one under test.
    private static func shadow() -> AnyCodable {
        [
            "type": "shadow", "shadowType": "outer", "offset": ["x": 8, "y": 8], "blur": 6,
            "color": "#FF8800", "blendMode": "normal", "enabled": true,
        ]
    }

    // MARK: - Pins

    /// One nested default held to the renderer.
    struct Pin: CustomTestStringConvertible {
        /// The nested shape the key belongs to (`fill`).
        let shape: String
        /// The variant's spelling, or `nil` for a shape with one form.
        var spelling: String?
        /// The keys from the object written to the key under test; the last is the key.
        let path: [String]
        /// The node property the object is written on (`fill`, `effect`, `strokeWidth`).
        let property: String
        /// The object, with the key under test unset.
        let object: AnyCodable
        /// A value that must draw differently from the default.
        let alternative: AnyCodable

        var testDescription: String {
            "\(shape) \(spelling ?? "") \(path.joined(separator: "."))"
        }
    }

    static let pins: [Pin] = [
        // Keys every fill carries, on the variants the CoreGraphics renderer draws.
        Pin(shape: "fill", spelling: "color", path: ["enabled"], property: "fill", object: color, alternative: false),
        Pin(shape: "fill", spelling: "color", path: ["blendMode"], property: "fill", object: color,
            alternative: "multiply"),
        Pin(shape: "fill", spelling: "gradient", path: ["enabled"], property: "fill", object: gradient(),
            alternative: false),
        Pin(shape: "fill", spelling: "gradient", path: ["blendMode"], property: "fill", object: gradient(),
            alternative: "multiply"),
        Pin(shape: "fill", spelling: "gradient", path: ["opacity"], property: "fill", object: gradient(),
            alternative: 0.4),
        Pin(shape: "fill", spelling: "image", path: ["enabled"], property: "fill", object: image, alternative: false),
        Pin(shape: "fill", spelling: "image", path: ["blendMode"], property: "fill", object: image,
            alternative: "multiply"),
        Pin(shape: "fill", spelling: "image", path: ["opacity"], property: "fill", object: image, alternative: 0.4),
        Pin(shape: "fill", spelling: "mesh_gradient", path: ["enabled"], property: "fill", object: mesh,
            alternative: false),
        Pin(shape: "fill", spelling: "mesh_gradient", path: ["blendMode"], property: "fill", object: mesh,
            alternative: "multiply"),
        Pin(shape: "fill", spelling: "mesh_gradient", path: ["opacity"], property: "fill", object: mesh,
            alternative: 0.4),
        // A gradient's frame.
        Pin(shape: "fill position", path: ["center", "x"], property: "fill", object: gradient(), alternative: 0.1),
        Pin(shape: "fill position", path: ["center", "y"], property: "fill", object: gradient(), alternative: 0.1),
        Pin(shape: "fill size", path: ["size", "width"], property: "fill", object: gradient([:], type: "radial"),
            alternative: 0.3),
        Pin(shape: "fill size", path: ["size", "height"], property: "fill", object: gradient([:], type: "radial"),
            alternative: 0.3),
        Pin(shape: "fill", spelling: "gradient", path: ["rotation"], property: "fill", object: gradient([:]),
            alternative: 60),
        // Effects.
        Pin(shape: "effect", spelling: "blur", path: ["enabled"], property: "effect",
            object: ["type": "blur", "radius": 6], alternative: false),
        Pin(shape: "effect", spelling: "blur", path: ["radius"], property: "effect",
            object: ["type": "blur"], alternative: 6),
        Pin(shape: "effect", spelling: "background_blur", path: ["enabled"], property: "effect",
            object: ["type": "background_blur", "radius": 6], alternative: false),
        Pin(shape: "effect", spelling: "background_blur", path: ["radius"], property: "effect",
            object: ["type": "background_blur"], alternative: 6),
        Pin(shape: "effect", spelling: "shadow", path: ["enabled"], property: "effect", object: shadow(),
            alternative: false),
        Pin(shape: "effect", spelling: "shadow", path: ["shadowType"], property: "effect", object: shadow(),
            alternative: "inner"),
        Pin(shape: "effect", spelling: "shadow", path: ["blur"], property: "effect",
            object: shadow(), alternative: 12),
        Pin(shape: "effect", spelling: "shadow", path: ["color"], property: "effect",
            object: shadow(), alternative: "#FF0000"),
        Pin(shape: "effect", spelling: "shadow", path: ["blendMode"], property: "effect", object: shadow(),
            alternative: "multiply"),
        // A per-side stroke width: a side left out carries no stroke.
        Pin(shape: "per-side width", path: ["top"], property: "strokeWidth",
            object: ["right": 3, "bottom": 3, "left": 3], alternative: 9),
        Pin(shape: "per-side width", path: ["right"], property: "strokeWidth",
            object: ["top": 3, "bottom": 3, "left": 3], alternative: 9),
        Pin(shape: "per-side width", path: ["bottom"], property: "strokeWidth",
            object: ["top": 3, "right": 3, "left": 3], alternative: 9),
        Pin(shape: "per-side width", path: ["left"], property: "strokeWidth",
            object: ["top": 3, "right": 3, "bottom": 3], alternative: 9),
    ]

    @Test("Leaving a nested key unset draws exactly as writing its default", arguments: pins)
    func unsetDrawsAsDefault(pin: Pin) throws {
        let field = try #require(Self.field(pin.shape, pin.spelling, pin.path.last ?? ""))
        let value = try #require(field.default?.value, "the schema lists no literal default")
        let key = pin.property

        let unset = try Self.draw(Self.document(key, pin.object.removing(pin.path), stroked: key == "strokeWidth"))
        let asDefault = try Self.draw(Self.document(key, pin.object.setting(pin.path, to: value), stroked: key == "strokeWidth"))
        let other = try Self.draw(Self.document(
            key, pin.object.setting(pin.path, to: pin.alternative), stroked: key == "strokeWidth"
        ))

        #expect(unset == asDefault, "the renderer does not draw an unset \(pin.path.joined(separator: ".")) as \(value)")
        #expect(unset != other, "the fixture does not exercise \(pin.path.joined(separator: "."))")
    }

    @Test("Every nested default the schema lists is pinned to the renderer")
    func everyNestedDefaultIsPinned() {
        let pinned = Set(Self.pins.map { Listed(shape: $0.shape, spelling: $0.spelling, key: $0.path.last ?? "") })
        #expect(pinned.count == Self.pins.count, "two pins name the same key")
        var listed: Set<Listed> = []
        for shape in PenSchema.nestedShapes {
            for variant in shape.variants {
                for field in variant.fields where field.default != nil {
                    let entry = Listed(shape: shape.name, spelling: variant.spelling, key: field.key)
                    listed.insert(entry)
                    #expect(pinned.contains(entry), "\(entry) = \(String(describing: field.default)) has no pin")
                }
            }
        }
        #expect(listed == pinned, "a pin names a key with no literal default")
    }

    @Test("The gradient frame's defaults are the ones the schema publishes")
    func gradientFrameDefaults() throws {
        let center = try #require(Self.field("fill position", nil, "x"))
        #expect(center.default == .number(0.5))
        #expect(Self.field("fill position", nil, "y")?.default == .number(0.5))
        #expect(Self.field("fill size", nil, "width")?.default == .number(1))
        #expect(Self.field("fill size", nil, "height")?.default == .number(1))
        #expect(Self.field("fill", "gradient", "rotation")?.default == .number(0))
        #expect(Self.field("fill", "gradient", "opacity")?.default == .number(1))
    }

    // MARK: - Lookup

    /// A nested key, by shape, variant spelling and key.
    private static func field(_ shape: String, _ spelling: String?, _ key: String) -> PenNestedShape.Field? {
        PenSchema.nestedShapes.first { $0.name == shape }?
            .variants.first { $0.spelling == spelling }?
            .fields.first { $0.key == key }
    }

    /// A nested key, for the coverage check.
    private struct Listed: Hashable {
        let shape: String
        let spelling: String?
        let key: String
    }

    // MARK: - Drawing

    private static let solidImage: CGImage? = {
        let context = CGContext(
            data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        context?.setFillColor(CGColor(srgbRed: 1, green: 0, blue: 1, alpha: 1))
        context?.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
        return context?.makeImage()
    }()

    private static func draw(_ fixture: AnyCodable) throws -> Data {
        let json = try String(decoding: JSONEncoder().encode(fixture), as: UTF8.self)
        let document = try PenParser.parse(json)
        let rects = PenLayoutEngine.layout(document)
        let image = try #require(PenRenderer.render(
            document, layoutRects: rects, size: CGSize(width: 400, height: 300),
            imageProvider: { _ in solidImage }
        ))
        return try #require(image.dataProvider?.data as Data?)
    }
}

private extension AnyCodable {
    /// The object with the value at `path` set, creating the objects on the way.
    func setting(_ path: [String], to value: AnyCodable) -> AnyCodable {
        guard case var .dictionary(entries) = self, let head = path.first else { return value }
        entries[head] = (entries[head] ?? .dictionary([:])).setting(Array(path.dropFirst()), to: value)
        return .dictionary(entries)
    }

    /// The object with the value at `path` removed.
    func removing(_ path: [String]) -> AnyCodable {
        guard case var .dictionary(entries) = self, let head = path.first else { return self }
        if path.count == 1 {
            entries.removeValue(forKey: head)
        } else if let child = entries[head] {
            entries[head] = child.removing(Array(path.dropFirst()))
        }
        return .dictionary(entries)
    }
}
