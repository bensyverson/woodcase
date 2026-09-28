//
//  ScriptMemberTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// The member table, read back from the prelude that defines it.
///
/// Two things depend on this being the runtime's own answer rather than a list kept
/// beside it: the sentence an unknown member earns, and the `.d.ts` `woodcase help js`
/// prints. Both are wrong the moment a member exists in one place and not the other.
@Suite("doc's member table")
struct ScriptMemberTests {
    /// A call of `member` with an options object in the slot that member keeps for one.
    ///
    /// The write members take a third positional argument — the properties, the subtree,
    /// the axis options — so "options are the second argument" stopped being true when
    /// they landed. The shapes are the ones the `.d.ts` declares; a member missing from
    /// this table fails the test rather than being skipped.
    ///
    /// - Parameters:
    ///   - member: The member to call.
    ///   - options: The body of the options object, as source.
    /// - Returns: The expression to run, or `nil` when the member takes no options slot.
    private func call(_ member: ScriptMember, options: String) -> String? {
        switch member.name {
        case "rev": nil
        case "set": "doc.set('Cnv01', { 'kind.content': 'x' }, { \(options) })"
        case "override": "doc.override('Chi01/Label', { content: 'x' }, { \(options) })"
        case "add", "replace": "doc.\(member.name)('Cnv01', { type: 'frame', name: 'X' }, { \(options) })"
        case "cp", "mv": "doc.\(member.name)('Cnv01', 'Brd01', { \(options) })"
        case "vars": nil
        case "themes": nil
        case "imports": nil
        case "vars.set": "doc.vars.set('brand', { type: 'string', value: 'x' }, { \(options) })"
        case "vars.rm": "doc.vars.rm('brand', { \(options) })"
        case "themes.set": "doc.themes.set('mode', ['light'], { \(options) })"
        case "themes.rm": "doc.themes.rm('mode', { \(options) })"
        case "imports.set": "doc.imports.set('V', './lib.pen', { \(options) })"
        case "imports.rm": "doc.imports.rm('V', { \(options) })"
        default: "doc.\(member.name)('Cnv01', { \(options) })"
        }
    }

    @Test("the table is every member, reads then writes, in declaration order")
    func theTableIsEveryMember() {
        #expect(ScriptHost.members().map(\.name) == [
            "rev", "tree", "get", "lint", "schema",
            "set", "add", "replace", "cp", "mv", "rm", "override",
            "vars", "vars.set", "vars.rm",
            "themes", "themes.set", "themes.rm",
            "imports", "imports.set", "imports.rm",
        ])
    }

    @Test("the top level is what doc itself exposes")
    func theTopLevelIsWhatDocExposes() {
        #expect(ScriptHost.topLevelMembers().map(\.name) == [
            "rev", "tree", "get", "lint", "schema",
            "set", "add", "replace", "cp", "mv", "rm", "override", "vars", "themes", "imports",
        ])
    }

    @Test("rev is read, the nested objects are namespaces, and the rest are called")
    func theKindsAreRight() {
        let kinds = Dictionary(
            uniqueKeysWithValues: ScriptHost.members().map { ($0.name, $0.kind) }
        )
        #expect(kinds["rev"] == .value)
        #expect(kinds["tree"] == .call)
        #expect(kinds["set"] == .call)
        #expect(kinds["vars"] == .namespace)
        #expect(kinds["themes"] == .namespace)
        #expect(kinds["imports"] == .namespace)
        #expect(kinds["vars.rm"] == .call)
    }

    @Test("every declared option key is one the member actually accepts")
    func theOptionKeysAreReal() throws {
        for member in ScriptHost.members() where member.kind == .call {
            for key in member.options {
                // `null` rather than a plausible value: it survives the "key was left out"
                // check, so the key itself is what gets looked up. The value is then
                // refused on its shape, which is a different code and not what is asked
                // here.
                let expression = try #require(
                    call(member, options: "\(key): null"),
                    "doc.\(member.name) declares options but this suite has no call shape for it"
                )
                let run = try ScriptHost.run(
                    [.text(expression, name: "<argv>")],
                    over: ScriptFixture.document("batch.pen")
                )
                #expect(
                    run.error?.code != ScriptErrorCode.unknownOption,
                    "doc.\(member.name) declares \(key) but refuses it"
                )
            }
        }
    }

    @Test("a key the table does not carry is refused, so the check above is not vacuous")
    func anUndeclaredKeyIsRefused() throws {
        for member in ScriptHost.members() where member.kind == .call {
            guard let expression = call(member, options: "notAKey: null") else { continue }
            let run = try ScriptHost.run(
                [.text(expression, name: "<argv>")],
                over: ScriptFixture.document("batch.pen")
            )
            #expect(
                run.error?.code == ScriptErrorCode.unknownOption,
                "doc.\(member.name) accepted an option nothing declares"
            )
        }
    }

    @Test("the sentence for an unknown member lists exactly the top level of the table")
    func theSentenceAndTheTableAgree() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run([.text("doc.nope", name: "<argv>")], over: document)
        let message = try #require(run.error?.message)
        let listed = ScriptHost.topLevelMembers().map(\.name).joined(separator: ", ")
        #expect(message.contains(listed))
    }

    @Test("the sentence for an unknown nested member lists exactly that namespace")
    func theNestedSentenceAndTheTableAgree() throws {
        let document = try ScriptFixture.document("batch.pen")
        for namespace in ScriptHost.members() where namespace.kind == .namespace {
            let run = ScriptHost.run(
                [.text("doc.\(namespace.name).nope", name: "<argv>")], over: document
            )
            let message = try #require(run.error?.message)
            let listed = ScriptHost.members()
                .filter { $0.name.hasPrefix("\(namespace.name).") }
                .map { String($0.name.dropFirst(namespace.name.count + 1)) }
                .joined(separator: ", ")
            #expect(message.contains(listed), "doc.\(namespace.name) did not list \(listed)")
        }
    }
}
