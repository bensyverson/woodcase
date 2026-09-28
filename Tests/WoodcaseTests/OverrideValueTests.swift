//
//  OverrideValueTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What `override` does with the two halves of a `key=value`: which vocabulary the key
/// is read in, and whether the value survives the merge that applies it.
@MainActor
struct OverrideValueTests {
    // MARK: - Fixture

    /// A `Button` component holding one text node, and one instance of it.
    private func makeDocument(componentID: String = "comp1") -> EditableDocument {
        let label = PenNode(
            id: "label",
            common: PenNodeCommon(name: "Label"),
            kind: .text(PenNode.TextData(content: .literal("Click")))
        )
        let component = PenNode(
            id: "comp1",
            common: PenNodeCommon(name: "Button", reusable: true),
            kind: .frame(PenNode.FrameData(children: [label]))
        )
        let instance = PenNode(
            id: "ref1",
            common: PenNodeCommon(name: "Submit"),
            kind: .ref(PenNode.RefData(ref: componentID))
        )
        return EditableDocument(from: PenDocument(children: [component, instance]))
    }

    /// The address of the label inside the instance.
    private func labelAddress() throws -> NodeAddress {
        try #require(NodeAddress("Submit/Label"))
    }

    /// The override entry the instance carries for one descendant key.
    private func stored(
        in document: EditableDocument,
        descendant key: String = "label"
    ) -> [String: AnyCodable] {
        guard case let .ref(data) = document.nodes["ref1"]?.kind else { return [:] }
        return data.descendants?[key]?.properties ?? [:]
    }

    /// The text the instance's label draws once the document is expanded — the only
    /// proof that an override *applied* rather than merely being stored.
    private func drawnLabel(of document: EditableDocument) -> String? {
        firstText(in: PenRefExpander.expand(document.materialize()).children)
    }

    private func firstText(in nodes: [PenNode]) -> String? {
        for node in nodes {
            if case let .text(data) = node.kind { return data.content?.literalValue }
            if let found = firstText(in: node.kind.inlineChildren) { return found }
        }
        return nil
    }

    // MARK: - Values

    @Test("The help's own example applies: a number on a text property is stored as text")
    func aNumberOnATextPropertyIsStoredAsText() throws {
        let document = makeDocument()

        _ = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: labelAddress(), props: ["content": .int(42)])),
            to: document
        )

        #expect(stored(in: document)["content"] == .string("42"))
        #expect(drawnLabel(of: document) == "42")
    }

    @Test("A coerced override echoes the divergence, the way a coerced set does")
    func aCoercedOverrideEchoesTheDivergence() throws {
        let document = makeDocument()

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: labelAddress(), props: ["content": .int(42)])),
            to: document
        )

        let divergence = try #require(result.divergences.first)
        #expect(divergence.kind == .coercion)
        #expect(divergence.target == "content")
        #expect(divergence.note == """
        content stored the number 42 as the text "42" — the property takes text, not a number
        """)
    }

    @Test("A value the node's type cannot take is refused, and nothing is stored")
    func aValueTheNodeCannotTakeIsRefused() throws {
        let document = makeDocument()
        let target = try labelAddress()

        var thrown: (any Error)?
        do {
            _ = try BatchApplier.applyOne(
                .override(BatchOperation.OverrideOp(
                    target: target, props: ["content": .dictionary(["a": .int(1)])]
                )),
                to: document
            )
        } catch {
            thrown = error
        }

        guard case let .overrideValueRejected(refID, descendantKey, key, expected, _)
            = try #require(thrown as? EditingError)
        else {
            Issue.record("expected an overrideValueRejected, got \(String(describing: thrown))")
            return
        }
        #expect(refID == "ref1")
        #expect(descendantKey == "label")
        #expect(key == "content")
        #expect(expected == NodePropertyCodec.expectedShape(of: "content"))
        #expect(stored(in: document).isEmpty)
        #expect(drawnLabel(of: document) == "Click")
    }

    @Test("The refusal names the descendant, what the property takes, and the read to run")
    func theRefusalTeaches() {
        let document = makeDocument()

        let message = BatchErrorMessage.describe(
            EditingError.overrideValueRejected(
                refID: "ref1", descendantKey: "label", key: "content",
                expected: "text or a $variable", actual: "an object"
            ),
            in: document,
            dialect: .command(file: "design.pen")
        )

        #expect(message.hasPrefix(
            "content on Submit/Label takes text or a $variable, but the value given is an object"
        ))
        #expect(message.contains("`woodcase get design.pen ref1/label`"))
    }

    @Test("A refusal reaches the document's own validate, so no peer ever sees it")
    func aRejectedValueIsRefusedByValidate() {
        let document = makeDocument()

        #expect(throws: (any Error).self) {
            try document.validate(.overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "ref1", descendantID: "label", properties: ["content": .dictionary([:])]
            )))
        }
    }

    @Test("An override whose component is not in the registry is not judged")
    func anUnresolvedComponentIsNotJudged() throws {
        let document = makeDocument(componentID: "gone")

        try document.apply(.overrideDescendant(EditOperation.OverrideDescendant(
            refNodeID: "ref1", descendantID: "label", properties: ["content": .dictionary([:])]
        )))

        #expect(stored(in: document)["content"] == .dictionary([:]))
    }

    @Test("An override carrying a type key replaces the node, so its keys are not judged")
    func aReplacementIsNotJudgedKeyByKey() throws {
        let document = makeDocument()

        _ = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(
                target: labelAddress(),
                props: ["type": .string("rectangle"), "width": .int(10)]
            )),
            to: document
        )

        #expect(stored(in: document)["type"] == .string("rectangle"))
    }

    // MARK: - Keys

    @Test("A kind. property path is translated to the raw key the map uses")
    func aKindPathIsTranslated() throws {
        let document = makeDocument()

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: labelAddress(), props: ["kind.content": .string("Menu")])),
            to: document
        )

        #expect(stored(in: document)["content"] == .string("Menu"))
        #expect(stored(in: document)["kind.content"] == nil)
        #expect(drawnLabel(of: document) == "Menu")
        #expect(result.divergences.isEmpty)
    }

    @Test("A common. property path is translated too")
    func aCommonPathIsTranslated() throws {
        let document = makeDocument()

        _ = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: labelAddress(), props: ["common.name": .string("Tag")])),
            to: document
        )

        #expect(stored(in: document)["name"] == .string("Tag"))
        #expect(stored(in: document)["common.name"] == nil)
    }

    @Test("A path whose JSON key differs takes the JSON spelling")
    func aRenamedFieldTakesItsJSONKey() throws {
        let document = makeDocument()

        _ = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(
                target: labelAddress(),
                props: ["kind.fills": .array([.dictionary(["type": .string("color"), "color": .string("#FFD166")])])]
            )),
            to: document
        )

        #expect(stored(in: document)["fill"] != nil)
        #expect(stored(in: document)["fills"] == nil)
    }

    @Test("A path written to a property the definition sets is not reported as a dead key")
    func aTranslatedPathIsNotADeadKey() throws {
        let document = makeDocument()

        let result = try BatchApplier.applyOne(
            .override(BatchOperation.OverrideOp(target: labelAddress(), props: ["kind.content": .int(7)])),
            to: document
        )

        #expect(result.divergences.map(\.kind) == [.coercion])
        #expect(drawnLabel(of: document) == "7")
    }
}
