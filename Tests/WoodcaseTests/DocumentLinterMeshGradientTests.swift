//
//  DocumentLinterMeshGradientTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `mesh-gradient-dropped` and `mesh-gradient-distorted`: a mesh fill Pen paints
/// nothing for, and one it paints but not as authored.
///
/// The Pen behaviour each case names was observed with the headless `pen` CLI
/// (`project/2026-09-26-what-pen-drops-from-a-file.md`); these tests hold the lint to it, and never run Pen.
@MainActor
struct DocumentLinterMeshGradientTests {
    // MARK: - Helpers

    /// A document whose one root is a 200×200 frame carrying `fill` (a JSON object).
    private func board(fill: String, key: String = "fill", type: String = "frame") throws -> EditableDocument {
        let json = """
        {"version": "2.17", "children": [
          {"type": "\(type)", "id": "Msh01", "name": "Mesh", "x": 0, "y": 0,
           "width": 200, "height": 200, "\(key)": \(fill)}
        ]}
        """
        return try EditableDocument(from: PenParser.parse(json))
    }

    /// A mesh fill with the given grid, colours and points, all as written.
    private func mesh(columns: Int? = 2, rows: Int? = 2, colors: String?, points: String?, extra: String = "")
        -> String
    {
        var keys = [#""type": "mesh_gradient""#]
        if let columns { keys.append(#""columns": \#(columns)"#) }
        if let rows { keys.append(#""rows": \#(rows)"#) }
        if let colors { keys.append(#""colors": \#(colors)"#) }
        if let points { keys.append(#""points": \#(points)"#) }
        if !extra.isEmpty { keys.append(extra) }
        return "{" + keys.joined(separator: ", ") + "}"
    }

    private static let fourColors = ##"["#FF0000", "#00FF00", "#0000FF", "#FFFF00"]"##
    private static let fourPoints = "[[0,0],[1,0],[0,1],[1,1]]"

    private func findings(_ document: EditableDocument, _ check: LintCheck) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document).filter { $0.check == check }
    }

    private func meshFindings(_ document: EditableDocument) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document).filter {
            $0.check == .meshGradientDropped || $0.check == .meshGradientDistorted
        }
    }

    // MARK: - The checks

    @Test("A mesh Pen drops is an error; one it distorts is a warning")
    func severities() {
        #expect(LintCheck.meshGradientDropped.rawValue == "mesh-gradient-dropped")
        #expect(LintCheck.meshGradientDropped.severity == .error)
        #expect(LintCheck.meshGradientDistorted.rawValue == "mesh-gradient-distorted")
        #expect(LintCheck.meshGradientDistorted.severity == .warning)
        #expect(!LintCheck.meshGradientDropped.summary.isEmpty)
        #expect(!LintCheck.meshGradientDistorted.summary.isEmpty)
    }

    // MARK: - Dropped

    @Test("Fewer points than columns × rows is a dropped fill")
    func pointCountMismatch() throws {
        let doc = try board(fill: mesh(colors: Self.fourColors, points: "[[0,0],[1,0],[0,1]]"))
        let found = try findings(doc, .meshGradientDropped)
        #expect(found.count == 1)
        let finding = try #require(found.first)
        #expect(finding.nodeID == "Msh01")
        #expect(finding.message.contains("3 points"))
        #expect(finding.message.contains("2×2"))
        #expect(finding.message.contains("removes"))
    }

    @Test("Fewer colours than columns × rows is a dropped fill")
    func colorCountMismatch() throws {
        let colors = ##"["#FF0000", "#00FF00", "#0000FF"]"##
        let doc = try board(fill: mesh(colors: colors, points: Self.fourPoints))
        let found = try findings(doc, .meshGradientDropped)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("3 colours") == true)
    }

    @Test("A mesh missing its points is a dropped fill")
    func missingPoints() throws {
        let doc = try board(fill: mesh(colors: Self.fourColors, points: nil))
        let found = try findings(doc, .meshGradientDropped)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("points") == true)
    }

    @Test("A mesh one row high paints nothing")
    func singleRow() throws {
        let doc = try board(fill: mesh(
            columns: 2, rows: 1, colors: ##"["#FF0000", "#00FF00"]"##, points: "[[0,0],[1,0]]"
        ))
        let found = try findings(doc, .meshGradientDropped)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("2×1") == true)
    }

    @Test("A mesh one column wide paints nothing")
    func singleColumn() throws {
        let doc = try board(fill: mesh(
            columns: 1, rows: 2, colors: ##"["#FF0000", "#00FF00"]"##, points: "[[0,0],[0,1]]"
        ))
        let found = try findings(doc, .meshGradientDropped)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("1×2") == true)
    }

    @Test("A mesh on a stroke is checked, and the finding says it is the stroke")
    func strokeMesh() throws {
        let doc = try board(
            fill: mesh(colors: Self.fourColors, points: "[[0,0],[1,0],[0,1]]"),
            key: "stroke",
            type: "rectangle"
        )
        let found = try findings(doc, .meshGradientDropped)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("stroke") == true)
    }

    @Test("A disabled mesh is not reported: nothing is painted either way")
    func disabledIsQuiet() throws {
        let doc = try board(fill: mesh(
            colors: Self.fourColors, points: "[[0,0],[1,0],[0,1]]", extra: #""enabled": false"#
        ))
        #expect(try meshFindings(doc).isEmpty)
    }

    // MARK: - Distorted: colours

    @Test("A 4-digit #RGBA colour is a distorted mesh, naming the colour")
    func rgbaColor() throws {
        let colors = ##"["#FF0000", "#0F0F", "#0000FF", "#FFFF00"]"##
        let doc = try board(fill: mesh(colors: colors, points: Self.fourPoints))
        let found = try findings(doc, .meshGradientDistorted)
        #expect(found.count == 1)
        let message = try #require(found.first?.message)
        #expect(message.contains("#0F0F"))
        #expect(message.contains("#00FF00FF"))
    }

    @Test(
        "A colour of any other length is a distorted mesh Pen paints nothing at",
        arguments: ["#FF000", "", "#", "#FF00000", "#FF0000FFF", "##F00", "F00#"]
    )
    func otherLengthColor(_ color: String) throws {
        let colors = ##"["#FF0000", "\##(color)", "#0000FF", "#FFFF00"]"##
        let doc = try board(fill: mesh(colors: colors, points: Self.fourPoints))
        let found = try findings(doc, .meshGradientDistorted)
        #expect(found.count == 1)
        let message = try #require(found.first?.message)
        #expect(message.contains("vertex 2 `\(color)`"), "\(message)")
        #expect(message.contains("reads as nothing"), "\(message)")
    }

    @Test(
        "A colour of a readable length with a digit that is not hex names the colour Pen reads",
        arguments: [("red", "#00EEDD"), ("#GGGGGG", "#000000"), ("#eGeGeG", "#00000E"), ("#FF0000FG", "#0FF0000F")]
    )
    func nonHexDigits(_ color: String, _ read: String) throws {
        let colors = ##"["#FF0000", "#00FF00", "#0000FF", "\##(color)"]"##
        let doc = try board(fill: mesh(colors: colors, points: Self.fourPoints))
        let found = try findings(doc, .meshGradientDistorted)
        #expect(found.count == 1)
        let message = try #require(found.first?.message)
        #expect(message.contains("vertex 4 `\(color)` as `\(read)`"), "\(message)")
    }

    @Test("3-, 6- and 8-digit hex colours are what Pen reads, and are clean")
    func otherHexFormsAreClean() throws {
        let colors = ##"["#F00", "00FF00", "#0000ff80", "#FF0"]"##
        let doc = try board(fill: mesh(colors: colors, points: Self.fourPoints))
        #expect(try meshFindings(doc).isEmpty)
    }

    // MARK: - Distorted: folds

    @Test("A patch whose handles cross folds over itself")
    func foldedPatch() throws {
        // The folded 2×2 from the mesh report's probe fixture (`mfold`).
        let points = """
        [{"position":[0,0],"rightHandle":[1.2,0.6],"bottomHandle":[0.6,1.2]},
         [1,0],[0,1],{"position":[1,1],"leftHandle":[-1.2,-0.6]}]
        """
        let doc = try board(fill: mesh(colors: Self.fourColors, points: points))
        let found = try findings(doc, .meshGradientDistorted)
        #expect(found.count == 1)
        #expect(found.first?.message.contains("folds") == true)
    }

    @Test("A fold in one patch of a 3×3 names that patch alone")
    func foldNamesItsPatch() throws {
        // The centre vertex is dragged past its right-hand neighbour, so the two
        // right-hand patches fold and the two left-hand ones only stretch.
        let colors = ##"["#000","#111","#222","#333","#444","#555","#666","#777","#888"]"##
        let points = "[[0,0],[0.5,0],[1,0],[0,0.5],[1.3,0.5],[1,0.5],[0,1],[0.5,1],[1,1]]"
        let doc = try board(fill: mesh(columns: 3, rows: 3, colors: colors, points: points))
        let found = try findings(doc, .meshGradientDistorted)
        #expect(found.count == 1)
        let message = try #require(found.first?.message)
        #expect(message.contains("column 2, row 1"))
        #expect(message.contains("column 2, row 2"))
        #expect(!message.contains("column 1, row 1"))
    }

    @Test("Every unfolded mesh of the mesh report's probe fixture lints clean")
    func probeMeshesAreClean() throws {
        let meshes = [
            mesh(colors: Self.fourColors, points: Self.fourPoints),
            mesh(
                columns: 3, rows: 3,
                colors: ##"["#1E3A8A","#1E3A8A","#1E3A8A","#1E3A8A","#F472B6","#1E3A8A","#FACC15","#1E3A8A","#10B981"]"##,
                points: """
                [[0,0],[0.5,0],[1,0],[0,0.5],{"position":[0.3,0.7],"leftHandle":[-0.2,0.1],
                "rightHandle":[0.2,-0.1],"topHandle":[0.05,-0.3],"bottomHandle":[-0.05,0.3]},
                [1,0.5],[0,1],[0.5,1],[1,1]]
                """
            ),
            mesh(
                columns: 3, rows: 2,
                colors: ##"["#000000","#FFFFFF","#000000","#FFFFFF","#000000","#FFFFFF"]"##,
                points: """
                [[0,0],{"position":[0.5,0],"bottomHandle":[0.25,0.4]},[1,0],[0,1],
                {"position":[0.5,1],"topHandle":[-0.25,-0.4]},[1,1]]
                """
            ),
            mesh(
                columns: 4, rows: 3,
                colors: ##"["#0F172A","#7C3AED","#DB2777","#F59E0B","#0EA5E9","#FFFFFF","#22C55E","#EF4444","#111827","#FDE047","#6366F1","#14B8A6"]"##,
                points: """
                [[0,0],[0.3333,0],[0.6667,0],[1,0],[0,0.5],[0.45,0.35],
                {"position":[0.6,0.7],"rightHandle":[0.15,0.2],"leftHandle":[-0.1,-0.05]},
                [1,0.5],[0,1],[0.3333,1],[0.6667,1],[1,1]]
                """
            ),
        ]
        for fill in meshes {
            #expect(try meshFindings(board(fill: fill)).isEmpty)
        }
    }
}
