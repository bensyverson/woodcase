//
//  PenStrokeMigrationRuleTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

/// Covers the 2.10 → 2.17 rewrite of the nested `stroke` object into flat keys.
struct PenStrokeMigrationRuleTests {
    // MARK: - Helpers

    private func migrated(
        _ node: [String: AnyCodable],
        diagnostics: PenDiagnosticCollector? = nil
    ) -> [String: AnyCodable] {
        var result = node
        let id: String? = if case let .string(value)? = node["id"] { value } else { nil }
        PenStrokeMigrationRule().apply(toNode: &result, id: id, diagnostics: diagnostics)
        return result
    }

    private func rectangle(
        id: String = "rect1",
        stroke: [String: AnyCodable]
    ) -> [String: AnyCodable] {
        [
            "id": .string(id),
            "type": .string("rectangle"),
            "stroke": .dictionary(stroke),
        ]
    }

    // MARK: - Key mapping

    @Test("The stroke fill becomes the flat stroke key")
    func fillBecomesStroke() {
        let node = migrated(rectangle(stroke: ["fill": .string("#000000")]))
        #expect(node["stroke"] == .string("#000000"))
    }

    @Test("A structured stroke fill survives as the flat stroke key")
    func structuredFillBecomesStroke() {
        let fill: AnyCodable = .dictionary(["type": .string("color"), "color": .string("#112233")])
        let node = migrated(rectangle(stroke: ["fill": fill]))
        #expect(node["stroke"] == fill)
    }

    @Test("thickness becomes strokeWidth")
    func thicknessBecomesStrokeWidth() {
        let node = migrated(rectangle(stroke: ["fill": .string("#000"), "thickness": .int(2)]))
        #expect(node["strokeWidth"] == .int(2))
        #expect(node["thickness"] == nil)
    }

    @Test("A per-side thickness object becomes a per-side strokeWidth object")
    func perSideThicknessBecomesStrokeWidth() {
        let perSide: AnyCodable = .dictionary([
            "top": .int(1), "right": .int(2), "bottom": .int(3), "left": .int(4),
        ])
        let node = migrated(rectangle(stroke: ["fill": .string("#0000FF"), "thickness": perSide]))
        #expect(node["strokeWidth"] == perSide)
    }

    @Test("A variable thickness is carried across unchanged")
    func variableThicknessSurvives() {
        let node = migrated(rectangle(stroke: ["fill": .string("#000"), "thickness": .string("$borderWidth")]))
        #expect(node["strokeWidth"] == .string("$borderWidth"))
    }

    @Test("join becomes strokeLinejoin")
    func joinBecomesLinejoin() {
        let node = migrated(rectangle(stroke: ["fill": .string("#000"), "join": .string("bevel")]))
        #expect(node["strokeLinejoin"] == .string("bevel"))
        #expect(node["join"] == nil)
    }

    @Test("cap becomes strokeLinecap")
    func capBecomesLinecap() {
        let node = migrated(rectangle(stroke: ["fill": .string("#000"), "cap": .string("round")]))
        #expect(node["strokeLinecap"] == .string("round"))
        #expect(node["cap"] == nil)
    }

    @Test("The legacy cap none becomes butt, which is the default and so is omitted")
    func capNoneBecomesButt() {
        let node = migrated(rectangle(stroke: ["fill": .string("#000"), "cap": .string("none")]))
        #expect(node["strokeLinecap"] == nil)
    }

    // MARK: - Alignment renames

    @Test("align inside becomes strokeAlignment inner")
    func insideBecomesInner() {
        let node = migrated(rectangle(stroke: ["fill": .string("#000"), "align": .string("inside")]))
        #expect(node["strokeAlignment"] == .string("inner"))
        #expect(node["align"] == nil)
    }

    @Test("align outside becomes strokeAlignment outer")
    func outsideBecomesOuter() {
        let node = migrated(rectangle(stroke: ["fill": .string("#000"), "align": .string("outside")]))
        #expect(node["strokeAlignment"] == .string("outer"))
    }

    // MARK: - Defaults Pen.app omits

    @Test("align center is the default and is omitted, as Pen.app writes it")
    func centerAlignmentIsOmitted() {
        let node = migrated(rectangle(stroke: ["fill": .string("#000"), "align": .string("center")]))
        #expect(node["strokeAlignment"] == nil)
    }

    @Test("join miter is the default and is omitted, as Pen.app writes it")
    func miterJoinIsOmitted() {
        let node = migrated(rectangle(stroke: ["fill": .string("#000"), "join": .string("miter")]))
        #expect(node["strokeLinejoin"] == nil)
    }

    // MARK: - Discarded properties

    @Test("dashPattern is discarded with a diagnostic naming the node")
    func dashPatternIsDiscarded() {
        let diagnostics = PenDiagnosticCollector()
        let node = migrated(
            rectangle(id: "dashed-stroke", stroke: [
                "fill": .string("#FF0000"),
                "dashPattern": .array([.int(5), .int(3)]),
            ]),
            diagnostics: diagnostics
        )
        #expect(node["dashPattern"] == nil)
        #expect(node["stroke"] == .string("#FF0000"))

        let reported = diagnostics.diagnostics.filter { $0.message.contains("dashPattern") }
        #expect(reported.count == 1)
        #expect(reported.first?.nodeID == "dashed-stroke")
        #expect(reported.first?.stage == .migration)
    }

    @Test("miterAngle is discarded with a diagnostic naming the node")
    func miterAngleIsDiscarded() {
        let diagnostics = PenDiagnosticCollector()
        let node = migrated(
            rectangle(id: "mitered", stroke: ["fill": .string("#000"), "miterAngle": .int(45)]),
            diagnostics: diagnostics
        )
        #expect(node["miterAngle"] == nil)

        let reported = diagnostics.diagnostics.filter { $0.message.contains("miterAngle") }
        #expect(reported.count == 1)
        #expect(reported.first?.nodeID == "mitered")
        #expect(reported.first?.stage == .migration)
    }

    // MARK: - Strokes with no paint

    @Test("A stroke with no fill is dropped entirely, as Pen.app drops it")
    func paintlessStrokeIsDropped() {
        let node = migrated(rectangle(stroke: [
            "align": .string("inside"),
            "thickness": .int(1),
            "join": .string("bevel"),
        ]))
        #expect(node["stroke"] == nil)
        #expect(node["strokeWidth"] == nil)
        #expect(node["strokeLinejoin"] == nil)
        #expect(node["strokeAlignment"] == nil)
    }

    @Test("A node with no stroke is left untouched")
    func nodeWithoutStrokeIsUntouched() {
        let node: [String: AnyCodable] = ["id": .string("rect1"), "type": .string("rectangle")]
        #expect(migrated(node) == node)
    }

    @Test("A stroke that is already flat is left untouched")
    func flatStrokeIsUntouched() {
        let node: [String: AnyCodable] = [
            "id": .string("rect1"),
            "type": .string("rectangle"),
            "stroke": .string("#000000"),
            "strokeWidth": .int(2),
        ]
        #expect(migrated(node) == node)
    }

    // MARK: - Registration and end-to-end

    @Test("The rule is registered with the legacy migrator")
    func ruleIsRegistered() {
        #expect(PenLegacyMigrator.rules.contains { $0 is PenStrokeMigrationRule })
    }

    @Test("A 2.9 document's strokes arrive flat through the parser's version gate")
    func parsesLegacyStrokeThroughTheGate() throws {
        let json = """
        {"version":"2.9","children":[{"id":"r","type":"rectangle","width":10,"height":10,
        "stroke":{"align":"outside","thickness":2,"cap":"square","dashPattern":[5,3],"fill":"#FF0000"}}]}
        """
        let diagnostics = PenDiagnosticCollector()
        let document = try PenParser.parse(Data(json.utf8), diagnostics: diagnostics)
        let data = try #require(document.children.first.flatMap { node -> PenNode.RectangleData? in
            if case let .rectangle(data) = node.kind { data } else { nil }
        })
        #expect(data.stroke == .single(.shorthand("#FF0000")))
        #expect(data.strokeWidth == .uniform(.literal(2)))
        #expect(data.strokeLinecap == .square)
        #expect(data.strokeAlignment == .outer)
        #expect(diagnostics.diagnostics.contains { $0.message.contains("dashPattern") && $0.nodeID == "r" })
    }
}
