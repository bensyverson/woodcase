#if os(macOS)

    import Foundation
    import Testing
    @testable import Woodcase

    /// Where an SVG export frames its roots and places each one: the canvas bounds, the
    /// ancestors' transforms and clips, and what is left out.
    struct SVGExporterGeometryTests {
        private typealias Fixture = SVGExportFixture

        /// Two parents, each with one child: `p1` plain at (100, 50), `p2` clipping at
        /// (300, 0) with a child that overhangs it.
        private static let twoParents = """
        [
          {"type": "frame", "id": "p1", "x": 100, "y": 50, "width": 100, "height": 100, "layout": "none",
           "fill": "#00FF00",
           "children": [
             {"type": "rectangle", "id": "a", "x": 10, "y": 20, "width": 30, "height": 40, "fill": "#FF0000"}
           ]},
          {"type": "frame", "id": "p2", "x": 300, "y": 0, "width": 50, "height": 50, "layout": "none", "clip": true,
           "children": [
             {"type": "rectangle", "id": "b", "x": 20, "y": 20, "width": 60, "height": 60, "fill": "#0000FF"}
           ]}
        ]
        """

        @Test("The root svg's viewBox and size are the bounds asked for, in points")
        func explicitBounds() throws {
            let fixture = try Fixture(Self.twoParents)
            let xml = try #require(try fixture.svg(["a"], bounds: PenRect(x: 100, y: 50, width: 80, height: 90)))
            let root = try #require(xml.rootElement())
            #expect(root.name == "svg")
            #expect(Fixture.attribute("viewBox", of: root) == "100 50 80 90")
            #expect(Fixture.attribute("width", of: root) == "80")
            #expect(Fixture.attribute("height", of: root) == "90")
            #expect(root.uri == "http://www.w3.org/2000/svg")
        }

        @Test("Without bounds, the roots' painted extents on the canvas frame the export")
        func defaultBoundsAreTheRootsUnion() throws {
            let fixture = try Fixture(Self.twoParents)
            let xml = try #require(try fixture.svg(["a", "b"]))
            let root = try #require(xml.rootElement())
            // a: (110, 70)–(140, 110); b: (320, 20)–(380, 80) — its own extent, not clipped.
            #expect(Fixture.attribute("viewBox", of: root) == "110 20 270 90")
        }

        @Test("A root is drawn at its absolute canvas position, through its parent's placement")
        func rootsAreAtCanvasPositions() throws {
            let fixture = try Fixture(Self.twoParents)
            let xml = try #require(try fixture.svg(["a"]))
            let paths = try Fixture.elements("path", in: xml)
            #expect(paths.count == 1, "only the root draws; its parent's fill does not")
            let transforms = try Fixture.elements("g", in: xml).compactMap { Fixture.attribute("transform", of: $0) }
            #expect(transforms.contains("matrix(1 0 0 1 100 50)"), "the parent's placement: \(transforms)")
            #expect(transforms.contains("matrix(1 0 0 1 10 20)"), "the root's own placement: \(transforms)")
        }

        @Test("A root under a clipping frame is cut to that frame, as on the canvas")
        func ancestorClipApplies() throws {
            let fixture = try Fixture(Self.twoParents)
            let xml = try #require(try fixture.svg(["b"]))
            let clips = try Fixture.elements("clipPath", in: xml)
            #expect(clips.count == 1)
            let clipID = try #require(clips.first.flatMap { Fixture.attribute("id", of: $0) })
            let users = try Fixture.elements("g", in: xml).filter { Fixture.attribute("clip-path", of: $0) == "url(#\(clipID))" }
            #expect(users.count == 1)
        }

        @Test("A rotated node carries its turn in its placement matrix")
        func rotationIsAMatrix() throws {
            let fixture = try Fixture("""
            [{"type": "rectangle", "id": "r", "x": 0, "y": 0, "width": 80, "height": 80, "rotation": 45, "fill": "#FF0000"}]
            """)
            let xml = try #require(try fixture.svg(["r"]))
            let matrices = try Fixture.elements("g", in: xml).compactMap { Fixture.attribute("transform", of: $0) }
            let turned = try #require(matrices.first)
            let numbers = turned.dropFirst("matrix(".count).dropLast().split(separator: " ").compactMap { Double($0) }
            #expect(numbers.count == 6)
            #expect(abs(abs(numbers[1]) - 0.7071) < 0.001, "b is ±sin 45°: \(turned)")
        }

        @Test("A root that is a descendant of another root is drawn once, inside its ancestor")
        func descendantRootIsDrawnOnce() throws {
            let fixture = try Fixture(Self.twoParents)
            let xml = try #require(try fixture.svg(["p1", "a"]))
            let reds = try Fixture.elements("path", in: xml).filter { Fixture.attribute("fill", of: $0) == "#ff0000" }
            #expect(reds.count == 1)
        }

        @Test("Roots are drawn in document order, whatever order they were named in")
        func documentOrder() throws {
            let fixture = try Fixture(Self.twoParents)
            let xml = try #require(try fixture.svg(["b", "a"]))
            let fills = try Fixture.elements("path", in: xml).compactMap { Fixture.attribute("fill", of: $0) }
            #expect(fills == ["#ff0000", "#0000ff"])
        }

        @Test("No root the document has answers nil rather than an empty picture")
        func unknownRootsAnswerNil() throws {
            let fixture = try Fixture(Self.twoParents)
            #expect(try fixture.svg(["nope"]) == nil)
            #expect(try fixture.svg([]) == nil)
        }

        @Test("A disabled root draws nothing but still answers an SVG of its bounds")
        func disabledRoot() throws {
            let fixture = try Fixture("""
            [{"type": "rectangle", "id": "r", "width": 10, "height": 10, "enabled": false, "fill": "#FF0000"}]
            """)
            let xml = try #require(try fixture.svg(["r"], bounds: PenRect(x: 0, y: 0, width: 10, height: 10)))
            #expect(try Fixture.elements("path", in: xml).isEmpty)
        }

        @Test("The one-subtree form draws a node in its parent's frame, as shot frames it")
        func subtreeInParentFrame() throws {
            let fixture = try Fixture(Self.twoParents)
            let data = try #require(SVGExporter.data(
                fixture.document, layoutRects: fixture.rects, rootNodeID: "a",
                region: PenRect(x: 10, y: 20, width: 30, height: 40)
            ))
            let xml = try XMLDocument(data: data)
            let root = try #require(xml.rootElement())
            #expect(Fixture.attribute("viewBox", of: root) == "10 20 30 40")
            let transforms = try Fixture.elements("g", in: xml).compactMap { Fixture.attribute("transform", of: $0) }
            #expect(!transforms.contains("matrix(1 0 0 1 100 50)"), "no ancestor placement: \(transforms)")
        }
    }

#endif
