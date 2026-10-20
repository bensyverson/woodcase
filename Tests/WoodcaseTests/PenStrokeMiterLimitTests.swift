import Foundation
import Testing
@testable import Woodcase

/// A stroke's miter limit: Pen's own 4 unless `metadata.woodcase.strokeMiterLimit` says
/// otherwise (leaf zRp9CO). The format has had no miter control since 2.17 dropped 2.10's
/// `miterAngle`.
///
/// The probes stroke an isosceles triangle 8 pt, centered, with a mitered apex: its miter
/// is 1 / sin(apex / 2) widths long, so a 25° apex (4.62) is beveled at Pen's limit of 4
/// and mitered at 10.
struct PenStrokeMiterLimitTests {
    /// A 25° isosceles triangle at 40, 20, 150 tall, stroked 8 pt black, its apex at
    /// (40 + 33.25, 20), with `woodcase` as its metadata keys.
    private func triangle(woodcase: String = "") -> String {
        let halfBase = 150 * tan(12.5 * Double.pi / 180)
        return """
        {"type": "path", "id": "t", "x": 40, "y": 20, "width": \(2 * halfBase), "height": 150,
         "stroke": "#000000", "strokeWidth": 8,
         "geometry": "M\(halfBase) 0 L\(2 * halfBase) 150 L0 150 Z",
         "metadata": {"type": "woodcase", "woodcase": {\(woodcase)}}}
        """
    }

    private func node(woodcase: String) throws -> PenNode {
        let document = try PenParser.parse(#"{"version": "2.19", "children": ["# + triangle(woodcase: woodcase) + "]}")
        return try #require(document.children.first)
    }

    /// The pixel 10 pt above the apex: inside a miter (which reaches 18.5 pt past it at a
    /// limit of 10), outside a bevel (which reaches about 1 pt).
    private func pastApex(_ grid: PixelGrid) -> PixelGrid.RGBA {
        grid.pixel(Int(40 + 150 * tan(12.5 * Double.pi / 180)), 10)
    }

    // MARK: - The node's limit

    @Test("With no key, a stroke's miter limit is Pen's: 4")
    func defaultIsPens() throws {
        #expect(try node(woodcase: "").strokeMiterLimit == 4)
        #expect(PenNode.defaultMiterLimit == 4)
    }

    @Test("metadata.woodcase.strokeMiterLimit sets it")
    func keySetsIt() throws {
        #expect(try node(woodcase: #""strokeMiterLimit": 10"#).strokeMiterLimit == 10)
        #expect(try node(woodcase: #""strokeMiterLimit": 1.5"#).strokeMiterLimit == 1.5)
    }

    @Test("A limit below 1, or one that is not a number, is Pen's", arguments: ["0.5", "-2", "\"10\"", "null", "[10]"])
    func unusableIsDefault(value: String) throws {
        #expect(try node(woodcase: #""strokeMiterLimit": \#(value)"#).strokeMiterLimit == 4)
    }

    // MARK: - CG

    @Test("The CG renderer bevels a 25° corner at Pen's limit, as Pen draws it")
    func rendererBevelsAtPensLimit() throws {
        let grid = try PenStrokeDashRendering.grid(triangle())
        #expect(pastApex(grid).a < 30, "beveled: \(pastApex(grid))")
    }

    @Test("The CG renderer miters a 25° corner when the node's limit allows it")
    func rendererMitersUnderAHigherLimit() throws {
        let grid = try PenStrokeDashRendering.grid(triangle(woodcase: #""strokeMiterLimit": 10"#))
        #expect(pastApex(grid).a > 200, "mitered: \(pastApex(grid))")
    }

    @Test("The painted extent counts a sharp polygon's miter only when the node's limit draws it")
    func paintedExtentFollowsTheLimit() throws {
        func polygon(_ woodcase: String) throws -> PenNode {
            let json = """
            {"version": "2.19", "children": [
              {"type": "polygon", "id": "p", "width": 40, "height": 150, "polygonCount": 3, "stroke": "#000000",
               "strokeWidth": 8, "metadata": {"type": "woodcase", "woodcase": {\(woodcase)}}}
            ]}
            """
            return try #require(PenParser.parse(json).children.first)
        }
        let box = PenRect(x: 0, y: 0, width: 40, height: 150)
        let low = try #require(PenLayoutEngine.localPaintedExtent(of: polygon(""), box: box, layoutRects: [:]))
        let high = try #require(PenLayoutEngine.localPaintedExtent(
            of: polygon(#""strokeMiterLimit": 100"#), box: box, layoutRects: [:]
        ))
        #expect(high.y < low.y - 10, "the apex's miter reaches far above it: \(high) vs \(low)")
    }

    // MARK: - Schema

    @Test("Every stroked shape with corners publishes the limit as a field, a factor of at least 1, default 4",
          arguments: [PenNode.NodeType.frame, .rectangle, .ellipse, .polygon, .path])
    func schemaField(type: PenNode.NodeType) throws {
        let row = try #require(PenSchema.field(PenMetadata.WoodcaseKey.strokeMiterLimit.propertyPath, for: type))
        #expect(row.default == .number(4))
        #expect(row.constraint == PenValueConstraint(unit: .factor, minimum: .inclusive(1)))
        #expect(row.key.written == "metadata.woodcase.strokeMiterLimit")
    }

    @Test("A line, which has no corners, and a node with no stroke take no limit field",
          arguments: [PenNode.NodeType.line, .text, .group, .icon, .note])
    func noSchemaField(type: PenNode.NodeType) {
        #expect(PenSchema.field(PenMetadata.WoodcaseKey.strokeMiterLimit.propertyPath, for: type) == nil)
    }

    @Test("A write below 1 is refused as out of range; 1 and above plan")
    @MainActor
    func writeBelowOneIsRefused() throws {
        let document = try EditableDocument(
            from: PenParser.parse(#"{"version": "2.19", "children": ["# + triangle() + "]}")
        )
        let path = PenMetadata.WoodcaseKey.strokeMiterLimit.propertyPath
        let refusal = try #require(try PlannerFixture.refusal(.set([path: 0.5]), at: "t", in: document))
        #expect(refusal.code == .outOfRange)
        #expect(try PlannerFixture.refusal(.set([path: 1]), at: "t", in: document) == nil)
    }
}
