//
//  SwiftUIEmitterMeshTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a mesh gradient fill becomes in emitted SwiftUI: always a native `MeshGradient`
/// (Ben's ruling, 2026-09-26), which the support file's `PenMeshGradient` style builds
/// from Pen's own grid — positions, the handles that differ from the grid's defaults, and
/// colours. ``SwiftUIRenderTests``
/// measures `render-mesh-gradients` against Pen's exports; these pin each decision.
struct SwiftUIEmitterMeshTests {
    private static let fourColors = ##"["#FF0000", "#00FF00", "#0000FF", "#FFFF00"]"##
    private static let fourColorCode = "colors: [Color(hex: 0xFF0000), Color(hex: 0x00FF00), Color(hex: 0x0000FF), Color(hex: 0xFFFF00)]"

    @Test("A plain 2×2 mesh is a PenMeshGradient of its bare points and colours, filling the shape")
    func plainMesh() throws {
        let code = try body(child: rect(fill: mesh(points: "[[0, 0], [1, 0], [0, 1], [1, 1]]")))
        #expect(code.contains(
            ".fill(PenMeshGradient(columns: 2, rows: 2, points: [[0, 0], [1, 0], [0, 1], [1, 1]], \(Self.fourColorCode)))"
        ))
    }

    @Test("A point keeps only the handles that differ from the grid's defaults, relative as Pen writes them")
    func handles() throws {
        // On a 3×3 grid the default handles reach ±0.125; the bottom one here is a default
        // written out, the others are not.
        let custom = ##"{"position": [0.3, 0.7], "leftHandle": [-0.2, 0.1], "rightHandle": [0.2, -0.1], "topHandle": [0.05, -0.3], "bottomHandle": [0, 0.125]}"##
        let points = "[[0, 0], [0.5, 0], [1, 0], [0, 0.5], \(custom), [1, 0.5], [0, 1], [0.5, 1], [1, 1]]"
        let colors = ##"["#000000", "#000000", "#000000", "#000000", "#FFFFFF", "#000000", "#000000", "#000000", "#000000"]"##
        let code = try body(child: rect(fill: mesh(columns: 3, rows: 3, colors: colors, points: points)))
        #expect(code.contains(
            "[0, 0.5], PenMeshVertex([0.3, 0.7], left: [-0.2, 0.1], right: [0.2, -0.1], top: [0.05, -0.3]), [1, 0.5]"
        ))
    }

    @Test("A point written as an object with only default handles is written bare")
    func defaultHandlesAreBare() throws {
        let points = ##"[{"position": [0, 0], "rightHandle": [0.25, 0]}, [1, 0], [0, 1], [1, 1]]"##
        let code = try body(child: rect(fill: mesh(points: points)))
        #expect(code.contains("points: [[0, 0], [1, 0], [0, 1], [1, 1]]"))
        #expect(!code.contains("PenMeshVertex("))
    }

    @Test("A translucent colour keeps its alpha, and the fill's opacity is the style's own")
    func opacity() throws {
        let colors = ##"["#FF000000", "#00FF00FF", "#0000FF80", "#FF00FFFF"]"##
        let code = try body(child: rect(fill: mesh(colors: colors, extra: ##""opacity": 0.7"##)))
        #expect(code.contains("colors: [Color(hex: 0xFF0000, opacity: 0), Color(hex: 0x00FF00), Color(hex: 0x0000FF, opacity: 0.502), Color(hex: 0xFF00FF)]"))
        #expect(code.contains("]).opacity(0.7))"))
    }

    @Test("A malformed colour is read as Pen's mesh reads it: a wrong length is clear, a word its digits")
    func malformedColourIsReadAsPenReadsIt() throws {
        let diagnostics = PenDiagnosticCollector()
        let colors = ##"["#FF0000", "#12345", "#eGeGeG", "red"]"##
        let code = try body(child: rect(fill: mesh(colors: colors)), diagnostics: diagnostics)
        #expect(code.contains(
            "colors: [Color(hex: 0xFF0000), Color(hex: 0x000000, opacity: 0), Color(hex: 0x00000E), Color(hex: 0x00EEDD)]"
        ))
        #expect(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics.map(\.message))")
    }

    @Test("A mesh on an ellipse fills the ellipse, over the node's box")
    func ellipse() throws {
        let child = ##"{"type": "ellipse", "id": "e", "width": 180, "height": 160, "fill": \##(mesh())}"##
        let code = try body(child: child)
        #expect(code.contains("Ellipse()"))
        #expect(code.contains(".fill(PenMeshGradient(columns: 2, rows: 2,"))
    }

    @Test("A frame with children paints its mesh as a background")
    func frameBackground() throws {
        let code = try body(child: rect(fill: ##""#FF0000""##), frame: ##""fill": \##(mesh()), "##)
        #expect(code.contains(".background(PenMeshGradient(columns: 2, rows: 2,"))
    }

    @Test("A folded mesh is still native, with its handles as written")
    func folded() throws {
        let points = ##"[{"position": [0, 0], "rightHandle": [1.2, 0.6], "bottomHandle": [0.6, 1.2]}, [1, 0], [0, 1], {"position": [1, 1], "leftHandle": [-1.2, -0.6]}]"##
        let code = try body(child: rect(fill: mesh(points: points)))
        #expect(code.contains(
            "points: [PenMeshVertex([0, 0], right: [1.2, 0.6], bottom: [0.6, 1.2]), [1, 0], [0, 1], PenMeshVertex([1, 1], left: [-1.2, -0.6])]"
        ))
    }

    @Test("A mesh Pen does not draw emits nothing and no warning: lint reports it")
    func droppedMesh() throws {
        let diagnostics = PenDiagnosticCollector()
        let missing = ##"{"type": "mesh_gradient", "columns": 2, "rows": 2}"##
        let code = try body(child: rect(fill: missing), diagnostics: diagnostics)
        #expect(!code.contains("MeshGradient"))
        #expect(!diagnostics.diagnostics.contains { $0.nodeID == "r" })

        let single = try body(child: rect(fill: mesh(columns: 2, rows: 1, colors: ##"["#FF0000", "#00FF00"]"##, points: "[[0, 0], [1, 0]]")))
        #expect(!single.contains("MeshGradient"))
    }

    @Test("A colour variable is read through the theme, and PenMeshGradient resolves it in the environment")
    func themedColour() throws {
        let diagnostics = PenDiagnosticCollector()
        let colors = ##"["$brand", "#00FF00", "$brand", "#FFFF00"]"##
        let document = ##""themes": {"mode": ["light", "dark"]}, "variables": {"brand": {"type": "color", "value": [{"theme": {"mode": "light"}, "value": "#FF0000"}, {"theme": {"mode": "dark"}, "value": "#0000FF"}]}}, "##
        let code = try body(child: rect(fill: mesh(colors: colors)), document: document, diagnostics: diagnostics)
        #expect(code.contains("@Environment(\\.penTheme) private var theme"))
        #expect(code.contains("colors: [theme.brand, Color(hex: 0x00FF00), theme.brand, Color(hex: 0xFFFF00)]"))
        #expect(diagnostics.diagnostics.isEmpty, "\(diagnostics.diagnostics.map(\.message))")
    }

    @Test("A colour variable the document does not declare is reported and the mesh is not drawn")
    func undeclaredColourVariable() throws {
        let diagnostics = PenDiagnosticCollector()
        let colors = ##"["$brand", "#00FF00", "#0000FF", "#FFFF00"]"##
        let code = try body(child: rect(fill: mesh(colors: colors)), diagnostics: diagnostics)
        #expect(!code.contains("MeshGradient"))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "r" && $0.message.contains("$brand") })
        #expect(!diagnostics.diagnostics.contains { $0.message.contains("mesh gradient fills") })
    }

    @Test("The support file resolves Pen's mesh to a native MeshGradient, subdivided, in device colour space")
    func supportTemplate() throws {
        let support = try #require(SwiftUIEmitter.supportTemplates()["PenSupport+Mesh.swift"])
        #expect(support.contains("struct PenMeshVertex"))
        #expect(support.contains("struct PenMeshGradient: ShapeStyle"))
        #expect(support.contains("func resolve(in environment: EnvironmentValues) -> MeshGradient"))
        #expect(support.contains("static let subdivisions = 8"))
        #expect(support.contains("smoothsColors: true"))
        #expect(support.contains("colorSpace: .device"))
        #expect(!support.contains("#available"))
    }

    // MARK: - Helpers

    private func mesh(
        columns: Int = 2, rows: Int = 2, colors: String = fourColors,
        points: String = "[[0, 0], [1, 0], [0, 1], [1, 1]]", extra: String = ""
    ) -> String {
        let tail = extra.isEmpty ? "" : ", \(extra)"
        return ##"{"type": "mesh_gradient", "columns": \##(columns), "rows": \##(rows), "colors": \##(colors), "points": \##(points)\##(tail)}"##
    }

    private func rect(fill: String) -> String {
        ##"{"type": "rectangle", "id": "r", "width": 200, "height": 120, "fill": \##(fill)}"##
    }

    /// The page `Board` holding `child`; `document` is extra top-level keys, each followed by
    /// a comma (`"variables": {…}, `).
    private func body(
        child: String, frame keys: String = "", document extra: String = "", diagnostics: PenDiagnosticCollector? = nil
    ) throws -> String {
        let json = ##"{"version": "2.17", \##(extra)"children": [{"type": "frame", "id": "root", "name": "Board", \##(keys)"children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
        return try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
    }
}
