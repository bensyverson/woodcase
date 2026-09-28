//
//  ScriptWriteRefusalTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// What the write members refuse, and what they say when they do.
///
/// The read side already proves that `doc` teaches rather than throwing a `TypeError`.
/// The write side has two shapes the read side does not: a third positional argument —
/// the properties or the subtree — and two nested objects, `vars` and `themes`, which
/// have to teach exactly as `doc` itself does or the lesson stops one level down.
@Suite("doc's writes refuse in sentences")
struct ScriptWriteRefusalTests {
    /// Runs one expression over the fixture and returns the failure.
    private func failure(of expression: String) throws -> ScriptError {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [.text(expression, name: "<argv>")],
            over: document,
            remedy: .command(file: "design.pen")
        )
        return try #require(run.error, "\(expression) should have thrown")
    }

    // MARK: - The member list

    @Test("an unknown member names the write members too")
    func theMemberListNamesTheWrites() throws {
        let error = try failure(of: "doc.setProps('a', {})")
        for member in ["set", "add", "replace", "cp", "mv", "rm", "override", "vars", "themes", "imports"] {
            #expect(error.message.contains(member), "the sentence should name \(member)")
        }
    }

    // MARK: - Nested objects

    @Test("an unknown member of doc.vars names the members vars has")
    func varsTeachesItsMembers() throws {
        let error = try failure(of: "doc.vars.remove('brand')")
        #expect(error.code == ScriptErrorCode.unknownMember)
        #expect(error.message.contains("doc.vars has no remove"))
        #expect(error.message.contains("set, rm"))
        #expect(error.message.contains("woodcase help js"))
    }

    @Test("an unknown member of doc.themes names the members themes has")
    func themesTeachesItsMembers() throws {
        let error = try failure(of: "doc.themes.add('mode', ['light'])")
        #expect(error.code == ScriptErrorCode.unknownMember)
        #expect(error.message.contains("doc.themes has no add"))
    }

    @Test("an unknown member of doc.imports names the members imports has")
    func importsTeachesItsMembers() throws {
        let error = try failure(of: "doc.imports.add('V', './lib.pen')")
        #expect(error.code == ScriptErrorCode.unknownMember)
        #expect(error.message.contains("doc.imports has no add"))
        #expect(error.message.contains("set, rm"))
    }

    @Test("an unknown option on a nested member names the keys it takes")
    func aNestedUnknownOptionTeaches() throws {
        let error = try failure(of: "doc.vars.rm('brand', { hard: true })")
        #expect(error.code == ScriptErrorCode.unknownOption)
        #expect(error.message.contains("doc.vars.rm has no option hard"))
        #expect(error.message.contains("force"))
    }

    @Test("a nested member that takes no options says so")
    func aNestedMemberWithNoOptionsSaysSo() throws {
        let error = try failure(of: "doc.themes.rm('mode', { cascade: true })")
        #expect(error.message.contains("doc.themes.rm takes no options"))
    }

    @Test("neither nested object can be used as a scratchpad")
    func theNestedObjectsRefuseAssignment() throws {
        #expect(try failure(of: "doc.vars.mine = 1;").message.contains("not a place to keep things"))
        #expect(try failure(of: "doc.themes.mine = 1;").message.contains("not a place to keep things"))
    }

    // MARK: - Options

    @Test("an unknown option key on a write names the keys that member takes")
    func anUnknownWriteOptionTeaches() throws {
        let error = try failure(of: "doc.set('Ttl01', { 'kind.content': 'x' }, { position: 0 })")
        #expect(error.code == ScriptErrorCode.unknownOption)
        #expect(error.message.contains("doc.set has no option position"))
        #expect(error.message.contains("rev"))
    }

    @Test("a CLI flag that has no option form here says what to write instead")
    func aRetiredWriteFlagIsExplained() throws {
        let error = try failure(of: "doc.cp('Cmp01', 'Crd01', { times: 3 })")
        #expect(error.code == ScriptErrorCode.unknownOption)
        #expect(error.message.contains("each"))
    }

    @Test("a tag is refused with the reason a program does not need one")
    func aTagIsRefused() throws {
        let error = try failure(of: "doc.add('Crd01', { type: 'frame', name: 'X' }, { tag: 'hero' })")
        #expect(error.code == ScriptErrorCode.unknownOption)
        #expect(error.message.contains("id"))
    }

    // MARK: - Positional arguments

    @Test("properties given as something other than an object say what to write")
    func propertiesMustBeAnObject() throws {
        let error = try failure(of: "doc.set('Ttl01', ['kind.content=x'])")
        #expect(error.code == ScriptErrorCode.badArgument)
        #expect(error.message.contains("kind.content"))
    }

    @Test("a set with no properties at all is refused before anything is applied")
    func aSetWithNoPropertiesIsRefused() throws {
        let error = try failure(of: "doc.set('Ttl01', {})")
        #expect(error.code == ScriptErrorCode.badArgument)
        #expect(error.message.contains("doc.set"))
    }

    @Test("an address where one is required teaches the address forms")
    func aMissingAddressTeaches() throws {
        let error = try failure(of: "doc.set(null, { 'kind.content': 'x' })")
        #expect(error.code == ScriptErrorCode.badArgument)
        #expect(error.message.contains("doc.set takes an address first"))
    }

    @Test("a subtree that is not an object says what a subtree is")
    func aSubtreeMustBeAnObject() throws {
        let error = try failure(of: "doc.add('Crd01', 'Third')")
        #expect(error.code == ScriptErrorCode.badArgument)
        #expect(error.message.contains("type"))
        #expect(error.message.contains("name"))
    }

    @Test("a subtree the format cannot read is refused with the decoder's reason")
    func anUnreadableSubtreeIsRefused() throws {
        let error = try failure(of: "doc.add('Crd01', { name: 'Third' })")
        #expect(error.code == ScriptErrorCode.badArgument)
        #expect(error.message.contains("type"))
    }

    @Test("a theme axis given something other than a list of options says so")
    func themeOptionsMustBeStrings() throws {
        let error = try failure(of: "doc.themes.set('mode', 'dark')")
        #expect(error.code == ScriptErrorCode.badArgument)
        #expect(error.message.contains("['light', 'dark']"))
    }

    @Test("a variable given something other than a definition says what one looks like")
    func aVariableNeedsATypeAndAValue() throws {
        let error = try failure(of: "doc.vars.set('brand', '#FF6600')")
        #expect(error.code == ScriptErrorCode.badArgument)
        #expect(error.message.contains("type"))
        #expect(error.message.contains("value"))
    }

    // MARK: - The editing layer's own refusals

    @Test("a write refused by the document carries the verb's sentence and code")
    func anEditingRefusalKeepsItsSentence() throws {
        let error = try failure(of: "doc.set('Ttl01', { 'kind.notAProperty': 1 })")
        #expect(error.code == "unknownProperty")
        #expect(error.message.contains("notAProperty"))
    }

    @Test("an ambiguous address inside a write carries its candidates")
    func anAmbiguousWriteCarriesCandidates() {
        let run = ScriptHost.run(
            [.text(
                """
                try { doc.set('Title', { 'kind.content': 'x' }); }
                catch (e) { e.candidates.map(c => c.id).sort(); }
                """,
                name: "<argv>"
            )],
            over: ScriptFixture.ambiguous()
        )
        #expect(run.error == nil)
        #expect(run.result == .array([.string("Ttl01"), .string("Ttl02")]))
    }

    @Test("removing a component that still has instances says so, with the flag that forces it")
    func removingAComponentWithInstancesIsRefused() throws {
        let error = try failure(of: "doc.rm('Cmp01')")
        #expect(error.code == "componentHasInstances")
    }

    @Test("a theme axis the document does not have cannot be removed")
    func removingAMissingAxisIsRefused() throws {
        let error = try failure(of: "doc.themes.rm('mode')")
        #expect(error.code == "themeAxisNotFound")
    }

    @Test("a variable the document does not have cannot be removed")
    func removingAMissingVariableIsRefused() throws {
        let error = try failure(of: "doc.vars.rm('brand')")
        #expect(error.code == "variableNotFound")
    }

    @Test("an import alias the document does not have cannot be removed")
    func removingAMissingAliasIsRefused() throws {
        let error = try failure(of: "doc.imports.rm('V')")
        #expect(error.code == "importNotFound")
    }

    // MARK: - The batch grammar's own refusals

    @Test("a refusal from the batch grammar carries its own case name as the code")
    func aBatchGrammarRefusalCarriesItsCode() throws {
        let error = try failure(of: "doc.set('Chi01/Label', { 'kind.content': 'x' })")
        #expect(error.code == "setInsideInstance", "BatchError.code should reach the script")
        #expect(error.message.contains("override"))
    }

    @Test("a stale rev on a root-level add is a document conflict, not a node one")
    func aRootLevelRevisionConflictNamesTheDocument() throws {
        let error = try failure(
            of: "doc.add(null, { type: 'frame', name: 'X' }, { rev: 'notarevision' })"
        )
        // Not `revisionConflict`: that pins one node, and a root-level line pins the
        // whole document. A caller re-reading before a retry needs to know which.
        #expect(error.code == "documentRevisionConflict")
    }
}
