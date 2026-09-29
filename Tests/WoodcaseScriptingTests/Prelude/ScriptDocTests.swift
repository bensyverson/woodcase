//
//  ScriptDocTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// What `doc` refuses, and what it says when it does.
///
/// The verbs' strength is that a refusal carries its own fix. A host that answered a
/// misspelled member with `TypeError: doc.setProps is not a function` would trade that
/// away on the very first mistake a model makes.
@Suite("doc refuses in sentences")
struct ScriptDocTests {
    /// Runs one expression over the fixture and returns the failure.
    private func failure(of expression: String, in document: EditableDocument? = nil) throws -> ScriptError {
        let document = try document ?? ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [.text(expression, name: "<argv>")],
            over: document,
            remedy: .command(file: "design.pen")
        )
        return try #require(run.error, "\(expression) should have thrown")
    }

    // MARK: - Members

    @Test("an unknown member names every real member")
    func anUnknownMemberNamesTheRealOnes() throws {
        let error = try failure(of: "doc.setProps('a', {})")
        #expect(error.code == ScriptErrorCode.unknownMember)
        #expect(error.message.contains("doc has no setProps"))
        for member in ["rev", "tree", "get", "lint", "schema"] {
            #expect(error.message.contains(member), "the sentence should name \(member)")
        }
        #expect(error.message.contains("woodcase help js"))
    }

    @Test("a script can catch the refusal and read its code")
    func aRefusalIsCatchable() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [.text(
                """
                try { doc.nope; } catch (e) {
                  ({ caught: e instanceof WoodcaseError, code: e.code });
                }
                """,
                name: "<argv>"
            )],
            over: document
        )
        #expect(run.error == nil)
        #expect(run.result == .dictionary([
            "caught": .bool(true),
            "code": .string(ScriptErrorCode.unknownMember),
        ]))
    }

    // MARK: - Options

    @Test("an unknown option key names the keys that member takes")
    func anUnknownOptionNamesTheRealKeys() throws {
        let error = try failure(of: "doc.tree('Cnv01', { position: 0 })")
        #expect(error.code == ScriptErrorCode.unknownOption)
        #expect(error.message.contains("doc.tree has no option position"))
        for key in ["depth", "expand", "props", "theme"] {
            #expect(error.message.contains(key), "the sentence should name \(key)")
        }
    }

    @Test("a flag that is only about printing says why it is not an option here")
    func aPrintingFlagIsExplained() throws {
        let error = try failure(of: "doc.tree('Cnv01', { absolute: true })")
        #expect(error.code == ScriptErrorCode.unknownOption)
        #expect(error.message.contains("absRect"))
    }

    @Test("a member that takes no options says so")
    func aMemberWithNoOptionsSaysSo() throws {
        let error = try failure(of: "doc.schema('text', { verbose: true })")
        #expect(error.message.contains("doc.schema takes no options"))
    }

    @Test("an option of the wrong shape says what shape it wants")
    func aBadOptionShapeIsRefused() throws {
        #expect(try failure(of: "doc.tree(null, { depth: -1 })").code == ScriptErrorCode.badArgument)
        #expect(try failure(of: "doc.tree(null, { expand: 'yes' })").code == ScriptErrorCode.badArgument)
        #expect(
            try failure(of: "doc.tree(null, { theme: ['mode=dark'] })").message.contains("{ mode: 'dark' }")
        )
        #expect(try failure(of: "doc.tree(null, { props: true })").message.contains("kind.fill"))
    }

    @Test("options passed where the address goes are redirected, not swallowed")
    func optionsInTheAddressSlotAreRedirected() throws {
        let error = try failure(of: "doc.tree({ depth: 1 })")
        #expect(error.code == ScriptErrorCode.badArgument)
        #expect(error.message.contains("doc.tree(null, { … })"))
    }

    @Test("an unknown lint check names the catalog")
    func anUnknownLintCheckNamesTheCatalog() throws {
        let error = try failure(of: "doc.lint(null, { exclude: ['clipped', 'nonsense'] })")
        #expect(error.code == ScriptErrorCode.badArgument)
        #expect(error.message.contains("clipped"))
        #expect(error.message.contains("woodcase lint --list"))
    }

    @Test("an unknown node type names every type")
    func anUnknownNodeTypeNamesThemAll() throws {
        let error = try failure(of: "doc.schema('textbox')")
        #expect(error.code == ScriptErrorCode.unknownNodeType)
        #expect(error.message.contains("textbox is not a node type"))
        #expect(error.message.contains("text"))
    }

    // MARK: - Addresses

    @Test("a missing address carries the verb's own sentence and its code")
    func aMissingAddressTeaches() throws {
        let error = try failure(of: "doc.get('Nope')")
        #expect(error.code == "addressNotFound")
        #expect(error.message.contains("Nope"))
    }

    @Test("an ambiguous address carries a candidates array a script can read")
    func anAmbiguousAddressCarriesCandidates() throws {
        let error = try failure(of: "doc.get('Title')", in: ScriptFixture.ambiguous())
        #expect(error.code == "ambiguousAddress")
        #expect(error.candidates.map(\.id).sorted() == ["Ttl01", "Ttl02"])
        #expect(error.candidates.contains { $0.path.contains("First") })
    }

    @Test("a script reads the candidates without parsing the sentence")
    func aScriptReadsTheCandidates() {
        let run = ScriptHost.run(
            [.text(
                """
                try { doc.get('Title'); } catch (e) {
                  e.candidates.map(c => c.id).sort();
                }
                """,
                name: "<argv>"
            )],
            over: ScriptFixture.ambiguous()
        )
        #expect(run.error == nil)
        #expect(run.result == .array([.string("Ttl01"), .string("Ttl02")]))
    }

    @Test("doc cannot be used as a scratchpad")
    func docRefusesAssignment() throws {
        let error = try failure(of: "doc.mine = 1;")
        #expect(error.message.contains("not a place to keep things"))
    }
}
