//
//  ReactEmitterMeshTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// How the React emitter paints a `mesh_gradient` fill: a small PNG raster from the mesh
/// core, as a `data:` URI background layer stretched over the box. Colors that change
/// with the theme get one raster per theme, switched through a CSS custom property in
/// `theme.css`, the way themed colors already are.
struct ReactEmitterMeshTests {
    // MARK: - Helpers

    /// Emits every file for a document, through the pipeline `woodcase generate react` runs.
    private func emit(_ document: PenDocument) -> [GeneratedFile] {
        ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        ).files
    }

    private func fixture() throws -> PenDocument {
        let url = try #require(
            Bundle.module.url(forResource: "react-mesh", withExtension: "pen", subdirectory: "Fixtures")
        )
        return try PenParser.parse(contentsOf: url)
    }

    private func file(_ path: String, in files: [GeneratedFile]) throws -> String {
        try #require(files.first { $0.path == path }).content
    }

    /// A one-component document whose root frame carries `fill`.
    private func document(fill: String, width: String = "200", height: String = "100") throws -> PenDocument {
        try PenParser.parse("""
        {"version": "2.17",
         "themes": {"mode": ["light", "dark"]},
         "variables": {"ink": {"type": "color", "value": "#00FF00"}},
         "children": [{"type": "frame", "id": "Box01", "name": "Box", "reusable": true,
           "width": \(width), "height": \(height), "fill": \(fill)}]}
        """)
    }

    private static let twoByTwo = """
    {"type": "mesh_gradient", "columns": 2, "rows": 2,
     "colors": ["#FF0000", "#00FF00", "#0000FF", "#FFFFFF"],
     "points": [[0, 0], [1, 0], [0, 1], [1, 1]]}
    """

    /// Every `data:` URI in `text`, in order.
    private func dataURIs(in text: String) -> [String] {
        text.matches(of: /data:image\/png;base64,[A-Za-z0-9+\/=]+/).map { String($0.output) }
    }

    #if canImport(ImageIO)
        /// The first `data:` URI in `text`, decoded.
        private func firstImage(in text: String) throws -> PNGTestDecoder {
            let uri = try #require(dataURIs(in: text).first)
            return try #require(PNGTestDecoder(dataURI: uri))
        }
    #endif

    // MARK: - Literal colors

    @Test("A mesh with literal colors paints a data-URI raster stretched over the box")
    func literalMeshEmitsDataURI() throws {
        let content = try file("components/Box.tsx", in: emit(document(fill: Self.twoByTwo)))
        #expect(content.contains(#"background: "url('data:image/png;base64,"#))
        #expect(content.contains(#"') center / 100% 100% no-repeat""#))
        #expect(dataURIs(in: content).count == 1)
    }

    @Test("A mesh whose variables are not themed is still baked inline")
    func unthemedVariableIsInlined() throws {
        let fill = """
        {"type": "mesh_gradient", "columns": 2, "rows": 2,
         "colors": ["$ink", "$ink", "#0000FF", "#0000FF"], "points": [[0, 0], [1, 0], [0, 1], [1, 1]]}
        """
        let content = try file("components/Box.tsx", in: emit(document(fill: fill)))
        #expect(dataURIs(in: content).count == 1)
        #expect(!content.contains("--wc-mesh-"))
    }

    @Test("A mesh Pen would not draw emits no background")
    func invalidMeshEmitsNothing() throws {
        let fill = """
        {"type": "mesh_gradient", "columns": 2, "rows": 2,
         "colors": ["#FF0000", "#00FF00", "#0000FF"], "points": [[0, 0], [1, 0], [0, 1], [1, 1]]}
        """
        let content = try file("components/Box.tsx", in: emit(document(fill: fill)))
        #expect(!content.contains("background"))
    }

    @Test("A mesh layers over the fills beneath it")
    func meshLayersOverFillsBeneath() throws {
        let content = try file("components/Box.tsx", in: emit(document(fill: "[\"#123456\", \(Self.twoByTwo)]")))
        #expect(content.contains(#"center / 100% 100% no-repeat, #123456""#))
    }

    #if canImport(ImageIO)
        @Test("The raster's corner pixels are the mesh's corner colors")
        func cornersMatchCornerColors() throws {
            let content = try file("components/Box.tsx", in: emit(document(fill: Self.twoByTwo)))
            let image = try firstImage(in: content)
            let last = (x: image.width - 1, y: image.height - 1)
            expectClose(image.rgba(x: 0, y: 0), [255, 0, 0, 255])
            expectClose(image.rgba(x: last.x, y: 0), [0, 255, 0, 255])
            expectClose(image.rgba(x: 0, y: last.y), [0, 0, 255, 255])
            expectClose(image.rgba(x: last.x, y: last.y), [255, 255, 255, 255])
        }

        @Test("A fixed box's raster is the box at 2 px per point by default")
        func rasterIsTheBoxAtTwoX() throws {
            let content = try file("components/Box.tsx", in: emit(document(fill: Self.twoByTwo)))
            let image = try firstImage(in: content)
            #expect(image.width == 400)
            #expect(image.height == 200)
        }

        @Test("The raster follows the scale the emitter is told")
        func rasterFollowsTheOptionsScale() throws {
            let document = try document(fill: Self.twoByTwo, width: "150", height: "100")
            let files = ReactEmitter.emit(
                document: document,
                components: ComponentAnalyzer.analyze(document),
                theme: ThemeAnalyzer.analyze(document),
                options: ReactEmitter.Options(meshRasterScale: 3)
            ).files
            let image = try firstImage(in: file("components/Box.tsx", in: files))
            #expect(image.width == 450)
            #expect(image.height == 300)
        }

        @Test("A very large box's raster is capped on its long side, proportional on the short one")
        func largeRasterIsCapped() throws {
            let content = try file("components/Box.tsx", in: emit(document(fill: Self.twoByTwo, width: "4000", height: "1000")))
            let image = try firstImage(in: content)
            #expect(image.width == ReactEmitter.meshRasterMaximumSide)
            #expect(image.height == ReactEmitter.meshRasterMaximumSide / 4)
        }

        @Test("A box with no fixed size gets a square raster")
        func unsizedBoxIsSquare() throws {
            let doc = try document(fill: Self.twoByTwo, width: "\"fill_container\"", height: "100")
            let content = try file("components/Box.tsx", in: emit(doc))
            let image = try firstImage(in: content)
            #expect(image.width == 64)
            #expect(image.height == 64)
        }

        @Test("The fill's opacity is baked into the raster's alpha")
        func opacityIsBaked() throws {
            let fill = """
            {"type": "mesh_gradient", "columns": 2, "rows": 2, "opacity": 0.5,
             "colors": ["#FF0000", "#FF0000", "#FF0000", "#FF0000"], "points": [[0, 0], [1, 0], [0, 1], [1, 1]]}
            """
            let content = try file("components/Box.tsx", in: emit(document(fill: fill)))
            let image = try firstImage(in: content)
            expectClose(image.rgba(x: 5, y: 5), [255, 0, 0, 128])
        }
    #endif

    // MARK: - Themed colors

    @Test("A mesh with themed colors paints through a custom property")
    func themedMeshUsesCustomProperty() throws {
        let content = try file("components/ThemedMesh.tsx", in: emit(fixture()))
        #expect(content.contains(#"background: "var(--wc-mesh-"#))
        #expect(content.contains(#") center / 100% 100% no-repeat, #FFFFFF""#))
        #expect(dataURIs(in: content).isEmpty)
    }

    @Test("theme.css defines the custom property once per theme")
    func themeCSSCarriesOneRasterPerTheme() throws {
        let files = try emit(fixture())
        let component = try file("components/ThemedMesh.tsx", in: files)
        let css = try file("theme.css", in: files)
        let name = try #require(component.firstMatch(of: /var\((--wc-mesh-[0-9a-f]+)\)/)).output.1
        let root = try #require(block(":root", in: css))
        let dark = try #require(block(#"[data-mode="dark"]"#, in: css))
        #expect(root.contains("\(name): url('data:image/png;base64,"))
        #expect(dark.contains("\(name): url('data:image/png;base64,"))
        #expect(dataURIs(in: root) != dataURIs(in: dark))
    }

    #if canImport(ImageIO)
        @Test("Each theme's raster carries that theme's corner colors")
        func themedRastersCarryThemeColors() throws {
            let css = try file("theme.css", in: emit(fixture()))
            let lightBlock = try #require(block(":root", in: css))
            let darkBlock = try #require(block(#"[data-mode="dark"]"#, in: css))
            let lightImage = try firstImage(in: lightBlock)
            let darkImage = try firstImage(in: darkBlock)
            let last = lightImage.width - 1
            // Opacity 0.8 → alpha 204.
            expectClose(lightImage.rgba(x: 0, y: 0), [255, 0, 0, 204])
            expectClose(lightImage.rgba(x: last, y: 0), [0, 0, 255, 204])
            expectClose(lightImage.rgba(x: 0, y: last), [0, 0, 0, 204])
            expectClose(darkImage.rgba(x: 0, y: 0), [0, 255, 255, 204])
            expectClose(darkImage.rgba(x: last, y: 0), [255, 255, 0, 204])
            expectClose(darkImage.rgba(x: last, y: last), [0, 255, 255, 204])
        }
    #endif

    // MARK: - Goldens

    @Test("MeshSwatch.tsx matches its golden")
    func meshSwatchGolden() throws {
        try GoldenFile.assert(file("components/MeshSwatch.tsx", in: emit(fixture())), name: "MeshSwatch.tsx", subdirectory: "mesh")
    }

    @Test("ThemedMesh.tsx matches its golden")
    func themedMeshGolden() throws {
        try GoldenFile.assert(file("components/ThemedMesh.tsx", in: emit(fixture())), name: "ThemedMesh.tsx", subdirectory: "mesh")
    }

    @Test("theme.css with a themed mesh matches its golden")
    func themeCSSGolden() throws {
        try GoldenFile.assert(file("theme.css", in: emit(fixture())), name: "theme.css", subdirectory: "mesh")
    }

    // MARK: - Assertions

    /// The body of the CSS rule whose selector is exactly `selector`.
    private func block(_ selector: String, in css: String) -> String? {
        guard let start = css.range(of: "\(selector) {\n") else { return nil }
        guard let end = css[start.upperBound...].range(of: "\n}") else { return nil }
        return String(css[start.upperBound ..< end.lowerBound])
    }

    /// Each channel within 3 of the expected value: the corner pixel's center sits half a
    /// pixel inside the mesh, and the color is rounded once.
    private func expectClose(_ actual: [Int], _ expected: [Int], sourceLocation: SourceLocation = #_sourceLocation) {
        let close = actual.count == expected.count && zip(actual, expected).allSatisfy { abs($0 - $1) <= 3 }
        #expect(close, "\(actual) is not within 3 of \(expected)", sourceLocation: sourceLocation)
    }
}
