import Foundation
import Testing
@testable import Woodcase

/// A dashed stroke lives in two `metadata.woodcase` keys — `strokeDash`, the alternating
/// dash and gap lengths, and `strokeDashOffset`, the phase — since the format has had no
/// dash since 2.17 (Ben's ruling, 2026-10-14; Penumbra's
/// `project/2026-10-14-feature-enhancements-plan.md` §1.4). ``PenNode/strokeDash`` is what
/// every target draws.
struct PenStrokeDashTests {
    /// A 100 × 60 rectangle stroked 4 pt red, with `metadata` and `width` as written.
    private func rectangle(woodcase: String, width: String = "4") throws -> PenNode {
        let json = """
        {"version": "2.19", "children": [
          {"type": "rectangle", "id": "r", "width": 100, "height": 60, "stroke": "#FF0000",
           "strokeWidth": \(width), "metadata": {"type": "woodcase", "woodcase": {\(woodcase)}}}
        ]}
        """
        return try #require(PenParser.parse(json).children.first)
    }

    // MARK: - Reading

    @Test("A node's dash is its lengths and its offset")
    func readsLengthsAndOffset() throws {
        let node = try rectangle(woodcase: #""strokeDash": [8, 4, 2, 4], "strokeDashOffset": 3"#)
        #expect(node.strokeDash == PenStrokeDash(lengths: [8, 4, 2, 4], phase: 3))
    }

    @Test("An absent offset is a phase of 0")
    func absentOffsetIsZero() throws {
        let node = try rectangle(woodcase: #""strokeDash": [6, 3]"#)
        #expect(node.strokeDash == PenStrokeDash(lengths: [6, 3], phase: 0))
    }

    @Test("No dash, or an empty one, is solid")
    func absentOrEmptyIsSolid() throws {
        #expect(try rectangle(woodcase: #""strokeDashOffset": 3"#).strokeDash == nil)
        #expect(try rectangle(woodcase: #""strokeDash": []"#).strokeDash == nil)
    }

    @Test("A dash no target can draw is solid: a negative length, all zeros, not numbers, or past 16 lengths",
          arguments: ["[-2, 4]", "[0, 0]", "[\"8\", 4]", "8", "[\(Array(repeating: "1", count: 17).joined(separator: ", "))]"])
    func malformedIsSolid(lengths: String) throws {
        let node = try rectangle(woodcase: #""strokeDash": "# + lengths)
        #expect(node.strokeDash == nil)
        #expect(try PenStrokeDash.problem(in: #require(node.common.metadata?[woodcase: .strokeDash])) != nil)
    }

    @Test("Sixteen lengths is the most a dash may have, and a zero-length dash between gaps is a dot")
    func limitsThatDraw() throws {
        let sixteen = Array(repeating: "2", count: 16).joined(separator: ", ")
        #expect(try rectangle(woodcase: #""strokeDash": ["# + sixteen + "]").strokeDash?.lengths.count == 16)
        #expect(try rectangle(woodcase: #""strokeDash": [0, 8]"#).strokeDash == PenStrokeDash(lengths: [0, 8], phase: 0))
    }

    @Test("A dash on a per-side stroke is solid: dashes flow around the whole outline, which per-side bands do not")
    func perSideIsSolid() throws {
        let node = try rectangle(woodcase: #""strokeDash": [8, 4]"#, width: #"{"top": 4, "bottom": 2}"#)
        #expect(node.strokeDash == nil)
    }

    // MARK: - Schema

    @Test("Every stroked shape publishes both keys as schema fields an inspector reads",
          arguments: [PenNode.NodeType.frame, .rectangle, .ellipse, .polygon, .path, .line])
    func schemaFields(type: PenNode.NodeType) throws {
        let dash = try #require(PenSchema.field(PenMetadata.WoodcaseKey.strokeDash.path, for: type))
        #expect(dash.default == .numbers([]))
        #expect(dash.constraint == .length)
        #expect(dash.value == "[number, …]")
        let offset = try #require(PenSchema.field(PenMetadata.WoodcaseKey.strokeDashOffset.path, for: type))
        #expect(offset.default == .number(0))
        #expect(offset.constraint?.unit == .points)
        #expect(offset.key.written == "metadata.woodcase.strokeDashOffset")
        // Beside locked, the miter limit (not on a line) and the shadow spread (leaf zRp9CO).
        let paths = PenSchema.woodcaseFields(for: type).map(\.path)
        #expect(paths.contains(PenMetadata.WoodcaseKey.locked.path))
        #expect(paths.contains(PenMetadata.WoodcaseKey.strokeDash.path))
        #expect(paths.contains(PenMetadata.WoodcaseKey.strokeDashOffset.path))
        #expect(paths == paths.sorted())
    }

    @Test("A node with no stroke of its own takes no dash field", arguments: [PenNode.NodeType.text, .note, .group, .icon])
    func noSchemaFieldWithoutStroke(type: PenNode.NodeType) {
        #expect(PenSchema.field(PenMetadata.WoodcaseKey.strokeDash.path, for: type) == nil)
        // A text, a group and an icon take the shadow spread (leaf zRp9CO), but no stroke key.
        #expect(!PenSchema.woodcaseFields(for: type).contains { $0.path.contains(".stroke") })
        #expect(PenSchema.woodcaseFields(for: type).map(\.path).contains(PenMetadata.WoodcaseKey.locked.path))
    }

    @Test("The schema's defaults draw as unset: an empty dash and a 0 offset are solid")
    func defaultsDrawAsUnset() throws {
        let unset = try PenStrokeDashRendering.pixels(woodcase: "")
        #expect(try PenStrokeDashRendering.pixels(woodcase: #""strokeDash": [], "strokeDashOffset": 0"#) == unset)
        #expect(try PenStrokeDashRendering.pixels(woodcase: #""strokeDash": [10, 10]"#) != unset)
    }
}
