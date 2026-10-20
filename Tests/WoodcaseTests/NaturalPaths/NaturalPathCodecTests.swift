//
//  NaturalPathCodecTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Reading and writing every Woodcase-owned key at its natural path: the codec turns the
/// path into the `metadata.woodcase` key it is stored under, keeping the rest of the
/// metadata, and the typed accessors read what was written (rules 1, 2 and 5).
@MainActor
struct NaturalPathCodecTests {
    private typealias Fixture = NaturalPathFixture

    // MARK: - Reading

    @Test("Each natural path reads the key it is stored under")
    func reads() throws {
        let card = try Fixture.node("Crd01")
        #expect(try NodePropertyCodec.value(at: "kind.strokeDash", of: card) == [8, 4])
        #expect(try NodePropertyCodec.value(at: "kind.strokeDashOffset", of: card) == 2)
        #expect(try NodePropertyCodec.value(at: "kind.strokeMiterLimit", of: card) == 10)
        #expect(try NodePropertyCodec.value(at: "common.locked", of: card) == true)
        let label = try Fixture.node("Lbl01")
        #expect(try NodePropertyCodec.value(at: "kind.defaultTextStyle", of: label) == true)
        guard case let .dictionary(spans) = try NodePropertyCodec.value(at: "kind.spans", of: label) else {
            Issue.record("kind.spans did not read an object")
            return
        }
        #expect(spans["text"] == .string("Hi there"))
    }

    @Test("An unset natural path reads null")
    func unsetReadsNull() throws {
        let plain = try Fixture.node("Pln01")
        #expect(try NodePropertyCodec.value(at: "kind.strokeDash", of: plain) == .null)
        #expect(try NodePropertyCodec.value(at: "common.locked", of: plain) == .null)
    }

    @Test("A natural path a type does not take is an unknown property there")
    func notOnEveryType() throws {
        #expect(throws: EditingError.self) {
            try NodePropertyCodec.value(at: "kind.strokeMiterLimit", of: Fixture.node("Lin01"))
        }
        #expect(throws: EditingError.self) {
            try NodePropertyCodec.value(at: "kind.spans", of: Fixture.node("Crd01"))
        }
    }

    // MARK: - Writing

    @Test("Writing a natural path stores it in metadata.woodcase and keeps the other keys")
    func writesStorage() throws {
        let card = try NodePropertyCodec.setting([4, 2], at: "kind.strokeDash", on: Fixture.node("Crd01"))
        #expect(card.strokeDash?.lengths == [4, 2])
        #expect(card.common.metadata?[woodcase: .strokeDash] == [4, 2])
        #expect(card.common.metadata?[woodcase: .locked] == true)
        #expect(card.blendMode == .multiply)

        let plain = try NodePropertyCodec.setting(true, at: "common.locked", on: Fixture.node("Pln01"))
        #expect(plain.isLocked)
        #expect(plain.common.metadata?.type == PenMetadata.woodcaseType)
    }

    @Test("Writing null to a natural path removes the key")
    func nullClears() throws {
        let card = try NodePropertyCodec.setting(.null, at: "common.locked", on: Fixture.node("Crd01"))
        #expect(!card.isLocked)
        #expect(card.common.metadata?[woodcase: .strokeDash] == [8, 4])
    }

    @Test("A planned set of every natural path writes metadata, and the typed accessors read it")
    func plannedSet() throws {
        let document = try Fixture.document()
        let plan = try EditPlanner.plan(
            .set([
                "kind.strokeDash": [4, 2], "kind.strokeDashOffset": 1, "kind.strokeMiterLimit": 8,
                "common.locked": true,
            ]),
            routedAt: .node(id: "Pln01"), in: document
        )
        for operation in plan.operations {
            guard case let .setProperties(write) = operation else { continue }
            #expect(write.properties.keys.sorted() == [NodePropertyCodec.metadataPath])
        }
        try Fixture.apply(plan, to: document)
        let plain = try #require(document.node(id: "Pln01"))
        #expect(plain.strokeDash?.lengths == [4, 2])
        #expect(plain.strokeDash?.phase == 1)
        #expect(plain.strokeMiterLimit == 8)
        #expect(plain.isLocked)
    }

    @Test("A planned set of a text's spans and default mark writes metadata")
    func plannedTextSet() throws {
        let document = try Fixture.document()
        let spans: AnyCodable = ["text": "Hi there", "runs": [["start": 3, "end": 8, "fontStyle": "italic"]]]
        let plan = try EditPlanner.plan(
            .set(["kind.spans": spans, "kind.defaultTextStyle": false]), routedAt: .node(id: "Lbl01"), in: document
        )
        try Fixture.apply(plan, to: document)
        let label = try #require(document.node(id: "Lbl01"))
        #expect(label.appliedRuns == [PenTextRun(start: 3, end: 8, isItalic: true)])
        #expect(label.common.metadata?[woodcase: .defaultTextStyle] == false)
    }

    @Test("A refusal of a natural path's value names the natural path")
    func refusalNamesNaturalPath() throws {
        let document = try Fixture.document()
        let range = try #require(PlannerFixture.refusal(.set(["kind.strokeDash": [-2, 4]]), at: "Board/Plain", in: document))
        #expect(range.code == .outOfRange)
        #expect(range.property == "kind.strokeDash")
        let form = try #require(PlannerFixture.refusal(.set(["common.locked": "yes"]), at: "Board/Plain", in: document))
        #expect(form.property == "common.locked")
    }

    @Test("A natural path written top-level in a file is read into metadata.woodcase")
    func topLevelMigrates() throws {
        let json = """
        {"version": "2.20", "children": [
          {"type": "rectangle", "id": "R", "width": 10, "height": 10, "strokeDash": [3, 1], "locked": true,
           "metadata": {"type": "woodcase", "woodcase": {"role": "card"}}}
        ]}
        """
        let node = try #require(EditableDocument(from: PenParser.parse(json)).node(id: "R"))
        #expect(node.strokeDash?.lengths == [3, 1])
        #expect(node.isLocked)
        #expect(node.common.metadata?[woodcase: .role] == .string("card"))
        #expect(node.extras.isEmpty)
    }

    @Test("A natural path write is a metadata change, so the diff and CRDT see one entry")
    func diffIsMetadata() throws {
        let card = try Fixture.node("Pln01")
        let locked = try NodePropertyCodec.setting(true, at: "common.locked", on: card)
        #expect(PropertyDiff.diffCommon(old: card.common, new: locked.common) == ["common.metadata"])
    }
}
