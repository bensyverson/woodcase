import Foundation
import Testing
@testable import Woodcase

/// A shadow's spread lives in `metadata.woodcase.shadowSpread`, since format 2.19 dropped
/// the key and Pen refuses a shadow that carries one (leaf zRp9CO). Each entry addresses
/// one effect by its place in the node's effects, and holds the shadow it was made for: when
/// Pen changes that effect — which keeps metadata but cannot see it — the entry is stale and
/// the shadow casts without spread.
struct PenShadowSpreadTests {
    private static let shadow = ##"{"type": "shadow", "shadowType": "outer", "offset": {"x": 0, "y": 4}, "blur": 8, "color": "#00000080"}"##

    /// A rectangle with `effect` and `woodcase` as its `metadata.woodcase` keys.
    private func rectangle(effect: String, woodcase: String) throws -> PenNode {
        let json = """
        {"version": "2.19", "children": [
          {"type": "rectangle", "id": "r", "width": 100, "height": 60, "fill": "#FFFFFF", "effect": \(effect),
           "metadata": {"type": "woodcase", "woodcase": {\(woodcase)}}}
        ]}
        """
        return try #require(PenParser.parse(json).children.first)
    }

    /// One entry, `spread` for effect `index`, made for `shadow`.
    private func entry(_ index: Int, _ spread: Double, shadow: String = Self.shadow) -> String {
        #"{"effect": \#(index), "spread": \#(spread), "shadow": \#(shadow)}"#
    }

    // MARK: - Applying

    @Test("A spread made for the shadow at its place applies")
    func freshSpreadApplies() throws {
        let node = try rectangle(effect: Self.shadow, woodcase: #""shadowSpread": [\#(entry(0, 4))]"#)
        #expect(node.shadowSpread(forEffect: 0) == 4)
        #expect(!node.hasStaleShadowSpread)
    }

    @Test("Each entry addresses its own effect by place")
    func entriesAddressEffectsByPlace() throws {
        let blur = #"{"type": "blur", "radius": 4}"#
        let inner = #"{"type": "shadow", "shadowType": "inner", "blur": 3}"#
        let node = try rectangle(
            effect: "[\(Self.shadow), \(blur), \(inner)]",
            woodcase: #""shadowSpread": [\#(entry(0, 4)), \#(entry(2, -2, shadow: inner))]"#
        )
        #expect(node.shadowSpread(forEffect: 0) == 4)
        #expect(node.shadowSpread(forEffect: 1) == nil)
        #expect(node.shadowSpread(forEffect: 2) == -2)
    }

    @Test("A spread survives what Pen does to an unchanged shadow on save: one effect in an array written alone, an absent color written #000000, keys reordered")
    func survivesPensRewrite() throws {
        let made = #"{"type": "shadow", "blur": 3, "offset": {"x": 2, "y": 2.5}}"#
        let saved = ##"{"color": "#000000", "type": "shadow", "shadowType": "outer", "offset": {"y": 2.5, "x": 2}, "blur": 3}"##
        let single = try rectangle(effect: saved, woodcase: #""shadowSpread": [\#(entry(0, 4, shadow: made))]"#)
        #expect(single.shadowSpread(forEffect: 0) == 4)
        let node = try rectangle(effect: "[\(saved)]", woodcase: #""shadowSpread": [\#(entry(0, 4, shadow: made))]"#)
        #expect(node.shadowSpread(forEffect: 0) == 4)
    }

    @Test("A hex color's case does not make a spread stale")
    func colorCaseIsIgnored() throws {
        let lower = Self.shadow.replacingOccurrences(of: "#00000080", with: "#ffaa0080")
        let upper = Self.shadow.replacingOccurrences(of: "#00000080", with: "#FFAA0080")
        let node = try rectangle(effect: upper, woodcase: #""shadowSpread": [\#(entry(0, 4, shadow: lower))]"#)
        #expect(node.shadowSpread(forEffect: 0) == 4)
    }

    // MARK: - Stale

    @Test("A spread is stale once its shadow changes, moves, or is gone",
          arguments: [
              ##"{"type": "shadow", "shadowType": "outer", "offset": {"x": 0, "y": 4}, "blur": 12, "color": "#00000080"}"##,
              ##"{"type": "shadow", "shadowType": "inner", "offset": {"x": 0, "y": 4}, "blur": 8, "color": "#00000080"}"##,
              ##"{"type": "shadow", "shadowType": "outer", "offset": {"x": 0, "y": 4}, "blur": 8, "color": "#FF000080"}"##,
              ##"[{"type": "blur", "radius": 4}, {"type": "shadow", "shadowType": "outer", "offset": {"x": 0, "y": 4}, "blur": 8, "color": "#00000080"}]"##,
              #"{"type": "blur", "radius": 4}"#,
              "[]",
          ])
    func changedShadowIsStale(effect: String) throws {
        let node = try rectangle(effect: effect, woodcase: #""shadowSpread": [\#(entry(0, 4))]"#)
        #expect(node.shadowSpread(forEffect: 0) == nil)
        #expect(node.hasStaleShadowSpread)
    }

    @Test("Entries that cannot be read apply to nothing",
          arguments: [
              #"{"effect": 0, "spread": 4}"#,
              #"[{"effect": -1, "spread": 4, "shadow": {"type": "shadow"}}]"#,
              #"[{"effect": 0, "spread": "4", "shadow": {"type": "shadow"}}]"#,
              #"[{"effect": 0, "spread": 4, "shadow": {"type": "blur"}}]"#,
              #"[{"effect": 0, "spread": 4, "shadow": {"type": "shadow"}, "extra": 1}]"#,
              #"[{"effect": 0, "spread": 4, "shadow": {"type": "shadow"}}, {"effect": 0, "spread": 2, "shadow": {"type": "shadow"}}]"#,
          ])
    func unreadableAppliesToNothing(value: String) throws {
        let node = try rectangle(effect: #"{"type": "shadow"}"#, woodcase: #""shadowSpread": \#(value)"#)
        #expect(node.shadowSpread(forEffect: 0) == nil)
        #expect(throws: PenShadowSpread.WireError.self) {
            _ = try PenShadowSpread.entries(in: node.common.metadata?[woodcase: .shadowSpread] ?? .null)
        }
    }

    // MARK: - Painted extent

    @Test("The painted extent counts a fresh spread, and not a stale one")
    func paintedExtentCountsSpread() throws {
        let plain = ##"{"type": "shadow", "blur": 0, "color": "#000000"}"##
        let box = PenRect(x: 0, y: 0, width: 100, height: 60)
        let spread = try rectangle(effect: plain, woodcase: #""shadowSpread": [\#(entry(0, 10, shadow: plain))]"#)
        let grown = try #require(PenLayoutEngine.localPaintedExtent(of: spread, box: box, layoutRects: [:]))
        #expect(grown == PenRect(x: -10, y: -10, width: 120, height: 80))
        let stale = try rectangle(effect: plain, woodcase: #""shadowSpread": [\#(entry(0, 10))]"#)
        #expect(PenLayoutEngine.localPaintedExtent(of: stale, box: box, layoutRects: [:]) == box)
    }

    // MARK: - Wire form

    @Test("Entries round-trip through their stored form")
    func roundTrip() throws {
        let shadow = PenEffect.PenShadowEffect(
            shadowType: .outer, offset: PenEffect.PenOffset(x: .literal(0), y: .literal(4)), blur: .literal(8),
            color: .literal("#00000080")
        )
        let entries = [PenShadowSpread(effect: 1, spread: 2.5, shadow: shadow)]
        let value = PenShadowSpread.metadataValue(of: entries)
        #expect(try PenShadowSpread.entries(in: value) == entries)
    }

    // MARK: - Schema

    @Test("Every node that takes effects publishes the spread as a field of its shadows", arguments: [
        PenNode.NodeType.frame, .rectangle, .ellipse, .polygon, .path, .text, .group, .icon,
    ])
    func schemaField(type: PenNode.NodeType) throws {
        // Was a row at the storage path; since oNeklc the spread is a field of the shadow.
        let row = try #require(PenSchema.field(NodePropertyCodec.effectsPath, for: type))
        let shadow = row.nested.first { $0.name == "effect" }?.variants.first { $0.spelling == "shadow" }
        #expect(shadow?.fields.contains { $0.key == "spread" } == true)
    }

    @Test("A spread that is not a number is refused, and a number is taken")
    @MainActor
    func malformedWriteIsRefused() throws {
        // Was a write of the storage path, which is refused since oNeklc; the spread is now
        // written on its shadow.
        let document = try EditableDocument(from: PenParser.parse("""
        {"version": "2.19", "children": [
          {"type": "rectangle", "id": "r", "width": 100, "height": 60, "effect": \(Self.shadow)}
        ]}
        """))
        let path = NodePropertyCodec.effectsPath
        let refusal = try #require(PlannerFixture.refusal(
            .set([path: .dictionary(["type": "shadow", "blur": 8, "spread": .array([4])])]), at: "r", in: document
        ))
        #expect(refusal.property == path)
        #expect(PlannerFixture.refusal(
            .set([path: .dictionary(["type": "shadow", "blur": 8, "spread": 4])]), at: "r", in: document
        ) == nil)
    }
}
