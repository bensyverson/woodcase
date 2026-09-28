//
//  NameInUseTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The one library answer to "is this name still referenced, and what do I say if it is".
///
/// The sentences are pinned byte for byte because two callers already print them —
/// `woodcase vars rm` and `doc.vars.rm` — and the whole point of the type is that they
/// stopped being two sentences.
struct NameInUseTests {
    /// The imports fixture: alias `V` is used by a ref and by a fill, `icons` by nothing.
    private func importDocument() throws -> EditableDocument {
        try EditableDocument(from: PenParser.parse(contentsOf: URL(
            fileURLWithPath: #filePath
        ).deletingLastPathComponent().appendingPathComponent("Fixtures/imports.pen")))
    }

    /// A document with one variable a text node binds its content to.
    private func variableDocument() -> EditableDocument {
        EditableDocument(from: PenDocument(
            variables: ["brand": PenVariable(type: .string, value: .simple(.string("Hi")))],
            children: [
                PenNode(
                    id: "Ttl01",
                    common: PenNodeCommon(name: "Title"),
                    kind: .text(PenNode.TextData(content: .variable("brand")))
                ),
            ]
        ))
    }

    // MARK: - Variables

    @Test("A variable nothing references is not in use")
    func anUnreferencedVariableIsFree() {
        let document = EditableDocument(from: PenDocument(
            variables: ["brand": PenVariable(type: .string, value: .simple(.string("Hi")))],
            children: []
        ))
        #expect(NameInUse.variable("brand", in: document).isEmpty)
    }

    @Test("A variable a node binds to is in use, and the sentence names the node's path")
    func aReferencedVariableNamesItsNodes() {
        let inUse = NameInUse.variable("brand", in: variableDocument())
        #expect(!inUse.isEmpty)
        #expect(inUse.count == 1)
        #expect(inUse.nodePaths == ["Title"])
    }

    @Test("The command dialect's remedy is --force, and it is the sentence vars rm printed")
    func theCommandSentenceIsUnchanged() {
        #expect(NameInUse.variable("brand", in: variableDocument()).sentence(in: .command(file: "x.pen")) == """
        Cannot remove brand: 1 node references it — Title. Pass --force to remove it anyway, \
        leaving those references unresolved.
        """)
    }

    @Test("The script dialect's remedy is the options object, and it is the sentence doc.vars.rm printed")
    func theScriptSentenceIsUnchanged() {
        #expect(NameInUse.variable("brand", in: variableDocument()).sentence(in: .script) == """
        Cannot remove brand: 1 node references it — Title. Pass `{ force: true }` to remove it \
        anyway, leaving those references unresolved.
        """)
    }

    @Test("A variable that resolves through another gets its own clause")
    func aVariableChainIsItsOwnClause() {
        let document = EditableDocument(from: PenDocument(
            variables: [
                "brand": PenVariable(type: .color, value: .simple(.string("#FF6600"))),
                "border": PenVariable(type: .color, value: .simple(.string("$brand"))),
            ],
            children: []
        ))
        let sentence = NameInUse.variable("brand", in: document).sentence(in: .command(file: "x.pen"))
        #expect(sentence.contains("1 variable resolves through it — border"))
    }

    @Test("More names than the cap are counted rather than printed")
    func alongListIsCapped() {
        let inUse = NameInUse(name: "brand", nodePaths: (1 ... 12).map { "Node\($0)" })
        let sentence = inUse.sentence(in: .command(file: "x.pen"))
        #expect(sentence.contains("12 nodes reference it"))
        #expect(sentence.contains("and 2 more"))
        #expect(!sentence.contains("Node11"))
    }

    // MARK: - Import aliases

    @Test("An alias a ref points into is in use, and so is one a variable reference names")
    func aReferencedAliasNamesItsNodes() throws {
        let inUse = try NameInUse.importAlias("V", in: importDocument())
        #expect(inUse.nodePaths == ["Canvas/Button", "Canvas/Title"])
    }

    @Test("An alias nothing reaches into is not in use")
    func anUnreferencedAliasIsFree() throws {
        #expect(try NameInUse.importAlias("icons", in: importDocument()).isEmpty)
    }

    @Test("The alias refusal is the same sentence, with the alias in the variable's place")
    func theAliasSentenceMatchesTheVariableOne() throws {
        #expect(try NameInUse.importAlias("V", in: importDocument())
            .sentence(in: .command(file: "x.pen")) == """
            Cannot remove V: 2 nodes reference it — Canvas/Button, Canvas/Title. Pass --force to \
            remove it anyway, leaving those references unresolved.
            """)
    }

    @Test("An alias that is a prefix of another does not answer for it")
    func aliasesDoNotBleedIntoEachOther() {
        let document = EditableDocument(from: PenDocument(
            imports: ["V": "./library.pen", "VV": "./other.pen"],
            children: [
                PenNode(
                    id: "Btn01",
                    common: PenNodeCommon(name: "Button"),
                    kind: .ref(PenNode.RefData(ref: "VV:Bt0aA"))
                ),
            ]
        ))
        #expect(NameInUse.importAlias("V", in: document).isEmpty)
        #expect(!NameInUse.importAlias("VV", in: document).isEmpty)
    }
}
