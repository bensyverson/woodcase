//
//  ShadowSpreadFieldTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A shadow's spread is a `spread` field on the shadow in `kind.effects` (leaf oNeklc;
/// `project/2026-10-20-natural-paths-for-woodcase-properties.md`): a write stores it in
/// `metadata.woodcase.shadowSpread`, one entry per spread shadow by its place, and a read
/// puts it back on its shadow. A whole `kind.effects` write restates every spread, so a
/// reordered or shortened list keeps each spread on its own shadow and drops the rest.
@MainActor
struct ShadowSpreadFieldTests {
    // MARK: - Fixture

    /// An outer shadow with no offset or blur, opaque black: it shows only where it is spread.
    private static let outer: AnyCodable = ["type": "shadow", "shadowType": "outer", "blur": 0, "color": "#000000"]
    /// The same shadow dropped 20 pt.
    private static let dropped: AnyCodable = [
        "type": "shadow", "offset": ["x": 0, "y": 20], "blur": 0, "color": "#000000",
    ]
    /// A layer blur, which takes no spread.
    private static let blur: AnyCodable = ["type": "blur", "radius": 2]

    private static func json(_ value: AnyCodable) -> String {
        PenPostIt.json(value)
    }

    /// `Card` has three effects, the first two spread 4 and 2; `Stale` holds a spread made
    /// for a shadow it no longer has; `Plain` has none; the component `Chip`'s `Box` spreads
    /// its shadow 4, and `Inst` draws the chip.
    private static let source = """
    {"version": "2.20", "children": [
      {"type": "frame", "id": "Brd", "name": "Board", "x": 0, "y": 0, "width": 400, "height": 300, "layout": "none",
       "children": [
        {"type": "rectangle", "id": "Crd", "name": "Card", "x": 40, "y": 30, "width": 60, "height": 40,
         "fill": "#FFFFFF", "effect": [\(json(outer)), \(json(dropped)), \(json(blur))],
         "metadata": {"type": "woodcase", "woodcase": {"locked": true, "shadowSpread": [
           {"effect": 0, "spread": 4, "shadow": \(json(outer))},
           {"effect": 1, "spread": 2, "shadow": \(json(dropped))}]}}},
        {"type": "rectangle", "id": "Stl", "name": "Stale", "x": 200, "y": 30, "width": 60, "height": 40,
         "effect": \(json(outer)),
         "metadata": {"type": "woodcase", "woodcase": {"shadowSpread": [
           {"effect": 0, "spread": 5, "shadow": \(json(dropped))}]}}},
        {"type": "rectangle", "id": "Pln", "name": "Plain", "x": 40, "y": 30, "width": 60, "height": 40,
         "fill": "#FFFFFF"},
        {"type": "frame", "id": "Chp", "name": "Chip", "reusable": true, "x": 200, "y": 150, "width": 80, "height": 40,
         "layout": "none", "children": [
          {"type": "rectangle", "id": "Box", "name": "Box", "x": 4, "y": 4, "width": 20, "height": 20,
           "effect": \(json(outer)),
           "metadata": {"type": "woodcase", "woodcase": {"shadowSpread": [
             {"effect": 0, "spread": 4, "shadow": \(json(outer))}]}}}]},
        {"type": "ref", "id": "Ins", "name": "Inst", "ref": "Chp", "x": 300, "y": 220}
      ]}
    ]}
    """

    private func document() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(Self.source))
    }

    /// A shadow object with a `spread` field.
    private static func spread(_ shadow: AnyCodable, _ points: AnyCodable) -> AnyCodable {
        guard case var .dictionary(object) = shadow else { return shadow }
        object["spread"] = points
        return .dictionary(object)
    }

    private func set(_ properties: [String: AnyCodable], on id: String, in document: EditableDocument) throws {
        try NaturalPathFixture.apply(EditPlanner.plan(.set(properties), routedAt: .node(id: id), in: document), to: document)
    }

    private func entries(_ id: String, in document: EditableDocument) -> [PenShadowSpread] {
        document.node(id: id)?.shadowSpreads ?? []
    }

    private func shadow(_ value: AnyCodable) throws -> PenEffect.PenShadowEffect {
        guard case let .shadow(shadow) = try AnyCodableDecoder.decode(PenEffect.self, from: value) else {
            throw CocoaError(.coderInvalidValue)
        }
        return shadow
    }

    /// The `spread` field of each effect a value holds, `nil` where an effect has none.
    private func spreads(in value: AnyCodable) -> [AnyCodable?] {
        let effects: [AnyCodable] = switch value {
        case let .array(items): items
        case .dictionary: [value]
        default: []
        }
        return effects.map { effect in
            guard case let .dictionary(object) = effect else { return nil }
            return object["spread"]
        }
    }

    // MARK: - Writing

    @Test("Writing kind.effects with a shadow spread 4 stores it in metadata.woodcase.shadowSpread")
    func writeStoresInMetadata() throws {
        let document = try document()
        try set([NodePropertyCodec.effectsPath: [Self.spread(Self.outer, 4)]], on: "Pln", in: document)
        let node = try #require(document.node(id: "Pln"))
        #expect(try entries("Pln", in: document) == [PenShadowSpread(effect: 0, spread: 4, shadow: shadow(Self.outer))])
        #expect(node.shadowSpread(forEffect: 0) == 4)
        guard case let .shadow(stored)? = PenRenderer.effects(for: node)?.all.first else {
            Issue.record("no shadow stored")
            return
        }
        #expect(stored.extras.isEmpty, "the spread left on the shadow: \(stored.extras)")
        #expect(try spreads(in: NodePropertyCodec.value(at: NodePropertyCodec.effectsPath, of: node)) == [nil])
    }

    @Test("The CG renderer draws a spread written through kind.effects")
    func rendererDrawsIt() throws {
        let document = try document()
        try set([NodePropertyCodec.effectsPath: [Self.spread(Self.outer, 4)]], on: "Pln", in: document)
        try document.apply(.setProperties(EditOperation.SetProperties(nodeID: "Crd", properties: ["common.x": 300])))
        let file = document.materialize()
        let image = try #require(PenRenderer.render(
            file, layoutRects: PenLayoutEngine.layout(file), size: CGSize(width: 200, height: 120)
        ))
        let grid = try #require(PixelGrid(image))
        let pixel = grid.pixel(38, 50)
        #expect(pixel.a > 200 && pixel.r < 40, "2 pt left of the shape, inside the spread: \(pixel)")
        let past = grid.pixel(30, 50)
        #expect(!(past.a > 200 && past.r < 40), "past the spread: \(past)")
    }

    @Test("A spread of 0 or null stores nothing, and the node's other metadata stays")
    func zeroStoresNothing() throws {
        let document = try document()
        try set([NodePropertyCodec.effectsPath: [Self.spread(Self.outer, 0), Self.spread(Self.dropped, .null)]],
                on: "Crd", in: document)
        let node = try #require(document.node(id: "Crd"))
        #expect(node.common.metadata?[woodcase: .shadowSpread] == nil)
        #expect(node.isLocked)
    }

    @Test("A spread that is not a number is refused at kind.effects")
    func badSpreadRefused() throws {
        let refusal = try #require(PlannerFixture.refusal(
            .set([NodePropertyCodec.effectsPath: [Self.spread(Self.outer, "wide")]]), at: "Pln", in: document()
        ))
        #expect(refusal.property == NodePropertyCodec.effectsPath)
        #expect(refusal.message.contains("a number of points for the spread"), "\(refusal.message)")
    }

    @Test("Writing the storage path is refused, naming kind.effects and the spread field")
    func storagePathRefused() throws {
        let refusal = try #require(PlannerFixture.refusal(
            .set([PenMetadata.WoodcaseKey.shadowSpread.path: .array([])]), at: "Card", in: document()
        ))
        #expect(refusal.code == .storedAtNaturalPath)
        #expect(refusal.message.contains(NodePropertyCodec.effectsPath), "\(refusal.message)")
        #expect(refusal.message.contains("spread"), "\(refusal.message)")
    }

    @Test("The codec's own write of kind.effects with a spread stores it in metadata too")
    func codecSettingFolds() throws {
        let plain = try #require(document().node(id: "Pln"))
        let node = try NodePropertyCodec.setting([Self.spread(Self.outer, 3)], at: NodePropertyCodec.effectsPath, on: plain)
        #expect(node.shadowSpread(forEffect: 0) == 3)
        guard case let .shadow(stored)? = PenRenderer.effects(for: node)?.all.first else {
            Issue.record("no shadow stored")
            return
        }
        #expect(stored.extras.isEmpty)
    }

    // MARK: - Reading

    @Test("Reading kind.effects returns each shadow with its own spread, and no stale one")
    func readsEachSpread() throws {
        let document = try document()
        let card = try #require(document.node(id: "Crd"))
        let value = try NodePropertyCodec.presentedValue(at: NodePropertyCodec.effectsPath, of: card)
        #expect(spreads(in: value) == [4, 2, nil])
        let stale = try #require(document.node(id: "Stl"))
        #expect(try spreads(in: NodePropertyCodec.presentedValue(at: NodePropertyCodec.effectsPath, of: stale)) == [nil])
    }

    @Test("get and tree --props print kind.effects with the spreads, and only where a node has one")
    func getAndTreePrintIt() throws {
        let document = try document()
        let card = try NodeLookup.find("Board/Card", in: document, expanding: false).report.properties
        #expect(spreads(in: card?[NodePropertyCodec.effectsPath] ?? .null) == [4, 2, nil])
        let plain = try NodeLookup.find("Board/Plain", in: document, expanding: false).report.properties
        #expect(plain?[NodePropertyCodec.effectsPath] == nil)

        let rows = try TreeView.rows(of: document, root: "Board/Card", properties: [NodePropertyCodec.effectsPath])
        #expect(spreads(in: rows.first?.properties?[NodePropertyCodec.effectsPath] ?? .null) == [4, 2, nil])
    }

    // MARK: - Reordering and removing

    @Test("Reordering and removing effects in one write keeps each spread on its own shadow")
    func reorderKeepsEach() throws {
        let document = try document()
        try set([NodePropertyCodec.effectsPath: [Self.blur, Self.spread(Self.dropped, 2)]], on: "Crd", in: document)
        #expect(try entries("Crd", in: document) == [PenShadowSpread(effect: 1, spread: 2, shadow: shadow(Self.dropped))])
        let card = try #require(document.node(id: "Crd"))
        #expect(card.shadowSpread(forEffect: 1) == 2)
        #expect(try spreads(in: NodePropertyCodec.presentedValue(at: NodePropertyCodec.effectsPath, of: card)) == [nil, 2])
        #expect(card.isLocked)
    }

    @Test("A whole kind.effects write with no spread drops every spread, a stale one too")
    func writeWithoutSpreadDropsThem() throws {
        let document = try document()
        try set([NodePropertyCodec.effectsPath: [Self.dropped, Self.outer]], on: "Crd", in: document)
        #expect(document.node(id: "Crd")?.common.metadata?[woodcase: .shadowSpread] == nil)
        try set([NodePropertyCodec.effectsPath: Self.outer], on: "Stl", in: document)
        #expect(document.node(id: "Stl")?.common.metadata?[woodcase: .shadowSpread] == nil)
    }

    @Test("Undo of a kind.effects write restores the effects and every spread entry, a stale one too")
    func undoRestores() throws {
        let original = try document()
        let session = DocumentSession(
            document: original.materialize(), author: Author(name: "ana", peerID: PeerID(rawValue: "peer-ana"))
        )
        let before = session.document.nodes["Stl"]
        let plan = try EditPlanner.plan(
            .set([NodePropertyCodec.effectsPath: [Self.spread(Self.dropped, 3)]]), routedAt: .node(id: "Stl"),
            in: session.document
        )
        try session.submit(.local(LocalEdit(operations: plan.operations)))
        #expect(session.document.nodes["Stl"]?.shadowSpread(forEffect: 0) == 3)
        try session.submit(.undo)
        #expect(session.document.nodes["Stl"] == before)
    }

    // MARK: - Instance overrides

    private static let box = ResolvedNodeAddress.instanceDescendant(refID: "Ins", descendantKey: "Box")

    private func override(_ properties: [String: AnyCodable], at target: ResolvedNodeAddress, in document: EditableDocument) throws {
        try NaturalPathFixture.apply(EditPlanner.plan(.override(properties, unset: []), at: target, in: document), to: document)
    }

    private func boxOverride(in document: EditableDocument) -> [String: AnyCodable]? {
        guard case let .ref(data)? = document.node(id: "Ins")?.kind else { return nil }
        return data.descendants?["Box"]?.properties
    }

    private func woodcase(_ properties: [String: AnyCodable]?) -> [String: AnyCodable]? {
        guard case let .dictionary(metadata)? = properties?["metadata"],
              case let .dictionary(keys)? = metadata[PenMetadata.woodcaseNamespace]
        else { return nil }
        return keys
    }

    @Test("An override of kind.effects with a spread stores it in the override's own metadata.woodcase")
    func overrideStoresInItsMetadata() throws {
        let document = try document()
        try override([NodePropertyCodec.effectsPath: [Self.spread(Self.dropped, 3)]], at: Self.box, in: document)
        let stored = boxOverride(in: document)
        #expect(spreads(in: stored?["effect"] ?? .null) == [nil])
        let entries = try PenShadowSpread.entries(in: woodcase(stored)?["shadowSpread"] ?? .null)
        #expect(try entries == [PenShadowSpread(effect: 0, spread: 3, shadow: shadow(Self.dropped))])
        let box = try #require(NaturalPathFixture.expanded("Ins/Box", in: document))
        #expect(box.shadowSpread(forEffect: 0) == 3)
        #expect(document.node(id: "Box")?.shadowSpread(forEffect: 0) == 4)
    }

    @Test("An override of kind.effects that names no spread inherits the component's, where its shadow still matches")
    func overrideWithoutSpreadInherits() throws {
        let document = try document()
        try override([NodePropertyCodec.effectsPath: [Self.outer]], at: Self.box, in: document)
        #expect(woodcase(boxOverride(in: document))?["shadowSpread"] == nil)
        #expect(NaturalPathFixture.expanded("Ins/Box", in: document)?.shadowSpread(forEffect: 0) == 4)
    }

    @Test("An override with spread 0 clears the component's spread on this instance only")
    func overrideZeroClears() throws {
        let document = try document()
        try override([NodePropertyCodec.effectsPath: [Self.spread(Self.outer, 0)]], at: Self.box, in: document)
        #expect(woodcase(boxOverride(in: document))?["shadowSpread"] == .array([]))
        #expect(NaturalPathFixture.expanded("Ins/Box", in: document)?.shadowSpread(forEffect: 0) == nil)
        #expect(document.node(id: "Box")?.shadowSpread(forEffect: 0) == 4)
    }

    @Test("An override of the instance root's effects with a spread stores it on the ref node's metadata")
    func rootOverrideStoresOnRef() throws {
        let document = try document()
        try override([NodePropertyCodec.effectsPath: [Self.spread(Self.outer, 6)]], at: .node(id: "Ins"), in: document)
        let ref = try #require(document.node(id: "Ins"))
        let entries = try PenShadowSpread.entries(in: ref.common.metadata?[woodcase: .shadowSpread] ?? .null)
        #expect(try entries == [PenShadowSpread(effect: 0, spread: 6, shadow: shadow(Self.outer))])
        guard case let .ref(data) = ref.kind else {
            Issue.record("not a ref")
            return
        }
        #expect(spreads(in: data.rootOverrides?["effect"] ?? .null) == [nil])
        let root = try #require(NaturalPathFixture.expanded("Ins/Chp", in: document))
        #expect(root.shadowSpread(forEffect: 0) == 6)
    }

    // MARK: - Schema

    @Test("The schema lists spread as a field of a shadow in kind.effects, and no separate shadowSpread row")
    func schema() throws {
        let row = try #require(PenSchema.field(NodePropertyCodec.effectsPath, for: .rectangle))
        let shape = try #require(row.nested.first { $0.name == "effect" })
        let shadow = try #require(shape.variants.first { $0.spelling == "shadow" })
        #expect(shadow.fields.contains { $0.key == "spread" })
        for type in PenNode.NodeType.allCases {
            #expect(!PenSchema.woodcaseFields(for: type).contains { $0.path == PenMetadata.WoodcaseKey.shadowSpread.path })
        }
    }
}
