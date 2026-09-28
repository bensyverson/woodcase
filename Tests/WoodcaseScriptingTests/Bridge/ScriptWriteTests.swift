//
//  ScriptWriteTests.swift
//  WoodcaseScriptingTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseScripting

/// The write members of `doc`: what they change, what they answer with, and what the
/// timeline records.
///
/// Every one of them is a translation of its arguments into a ``Woodcase/BatchOperation``
/// and a call to ``Woodcase/BatchApplier/applyOne(_:to:recorder:log:file:)``. So these
/// tests are about the *translation* — that `at` reaches the operation, that the report
/// carries the ids — and never about what an edit means, which is the applier's and is
/// tested where it lives.
@Suite("doc writes")
struct ScriptWriteTests {
    /// Runs one script over a document and requires it to have succeeded.
    private func run(_ body: String, over document: EditableDocument) throws -> ScriptRun {
        let run = ScriptHost.run([.text(body, name: "<argv>")], over: document)
        #expect(run.error == nil, "the script failed: \(run.error?.message ?? "")")
        return run
    }

    /// The object a script's last expression returned.
    private func fields(of run: ScriptRun) throws -> [String: AnyCodable] {
        guard case let .dictionary(fields) = try #require(run.result) else {
            Issue.record("a write should answer with an object")
            return [:]
        }
        return fields
    }

    /// A text node's content as it is stored, when it is a literal.
    private func content(of id: String, in document: EditableDocument) -> String? {
        guard case let .text(data) = document.nodes[id]?.kind else { return nil }
        return data.content?.literalValue
    }

    /// The variable a text node's content names, when it is a reference.
    private func contentVariable(of id: String, in document: EditableDocument) -> String? {
        guard case let .text(data) = document.nodes[id]?.kind else { return nil }
        return data.content?.variableName
    }

    /// A string field of a returned object.
    private func string(_ key: String, in fields: [String: AnyCodable]) throws -> String {
        guard case let .string(value) = try #require(fields[key], "\(key) is missing") else {
            Issue.record("\(key) should be a string")
            return ""
        }
        return value
    }

    // MARK: - set

    @Test("doc.set patches the node and answers with the write report")
    func setPatchesAndReports() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run("doc.set('Ttl01', { 'kind.content': 'Hello' })", over: document)
        let report = try fields(of: run)
        #expect(report["id"] == .string("Ttl01"))
        #expect(report["path"] == .string("Canvas/Title"))
        #expect(report["nodeRevision"] == .string(document.revision(of: "Ttl01") ?? ""))
        #expect(report["documentRevision"] == .string(document.documentRevision))
        #expect(content(of: "Ttl01", in: document) == "Hello")
    }

    @Test("every write is one event on the timeline, in order")
    func writesReachTheTimeline() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run(
            """
            doc.set('Ttl01', { 'kind.content': 'One' });
            console.log('between');
            doc.set('Ttl01', { 'kind.content': 'Two' });
            """,
            over: document
        )
        let shapes: [String] = run.events.map { event in
            switch event {
            case .write: "write"
            case .log: "log"
            case .warning: "warning"
            case .overlap: "overlap"
            }
        }
        #expect(shapes == ["write", "log", "write"])
    }

    @Test("every write event names the member that made it")
    func writesNameTheirMember() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run(
            """
            doc.set('Ttl01', { 'kind.content': 'One' });
            doc.cp('Chip', 'Board', { props: { 'common.name': 'Chip 2' } });
            doc.vars.set('brand', { type: 'color', value: '#FF6600' });
            doc.vars.rm('brand');
            doc.rm('Ttl01');
            """,
            over: document
        )
        let members: [ScriptWriteMember] = run.events.compactMap { event in
            if case let .write(member, _) = event { member } else { nil }
        }
        #expect(members == [.set, .cp, .varsSet, .varsRemove, .rm])
    }

    @Test("the sink sees each write as it happens")
    func theSinkSeesWrites() throws {
        let document = try ScriptFixture.document("batch.pen")
        var paths: [String] = []
        let run = ScriptHost.run(
            [.text(
                "doc.set('Ttl01', { 'kind.content': 'Hi' }); doc.set('Cd101', { 'kind.width': 120 });",
                name: "<argv>"
            )],
            over: document
        ) { event in
            if case let .write(_, report) = event, let path = report.path { paths.append(path) }
        }
        #expect(run.error == nil)
        #expect(paths == ["Canvas/Title", "Canvas/Cards/First"])
    }

    @Test("a rev that no longer matches throws revisionConflict, catchably")
    func aStaleRevisionConflicts() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run(
            """
            try {
              doc.set('Ttl01', { 'kind.content': 'Hello' }, { rev: 'notarevision' });
            } catch (e) { ({ code: e.code, woodcase: e instanceof WoodcaseError }); }
            """,
            over: document
        )
        #expect(run.result == .dictionary([
            "code": .string("revisionConflict"),
            "woodcase": .bool(true),
        ]))
    }

    @Test("a rev read back from the last write lets the next one through")
    func aFreshRevisionIsAccepted() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run(
            """
            const first = doc.set('Ttl01', { 'kind.content': 'One' });
            doc.set('Ttl01', { 'kind.content': 'Two' }, { rev: first.nodeRevision }).path;
            """,
            over: document
        )
        #expect(run.result == .string("Canvas/Title"))
    }

    // MARK: - Typed values

    @Test("an integer written from a script is stored as an integer")
    func anIntegerStaysAnInteger() throws {
        let scripted = try ScriptFixture.document("batch.pen")
        _ = try run("doc.set('Ttl01', { 'kind.fontSize': 18 })", over: scripted)

        let applied = try ScriptFixture.document("batch.pen")
        try BatchApplier.applyOne(
            .set(BatchOperation.SetOp(
                target: #require(NodeAddress("Ttl01")),
                props: ["kind.fontSize": .int(18)]
            )),
            to: applied
        )
        #expect(scripted.documentRevision == applied.documentRevision)
        #expect(scripted.materialize() == applied.materialize())
    }

    @Test("a $variable value stays a variable reference, not a coerced literal")
    func aVariableReferenceStaysAReference() throws {
        let document = try ScriptFixture.document("batch.pen")
        _ = try run("doc.set('Ttl01', { 'kind.content': '$label' })", over: document)
        #expect(contentVariable(of: "Ttl01", in: document) == "label")
    }

    // MARK: - add, replace, cp, mv, rm

    @Test("doc.add answers with the created subtree and its ids")
    func addAnswersWithCreatedIDs() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run(
            "doc.add('Crd01', { type: 'frame', name: 'Third', width: 100, height: 60 }, { at: 0 })",
            over: document
        )
        let report = try fields(of: run)
        let id = try string("id", in: report)
        #expect(document.nodes[id]?.common.name == "Third")
        #expect(document.childIDs(of: "Crd01").first == id)
        guard case let .array(created) = try #require(report["created"]) else {
            Issue.record("add should answer with a created tree")
            return
        }
        #expect(created.count == 1)
    }

    @Test("doc.add with a null parent adds at the document root")
    func addAtTheRoot() throws {
        let document = try ScriptFixture.document("batch.pen")
        let before = document.rootOrder.count
        _ = try run("doc.add(null, { type: 'frame', name: 'Loose', width: 10, height: 10 })", over: document)
        #expect(document.rootOrder.count == before + 1)
    }

    @Test("doc.replace swaps the subtree in place")
    func replaceSwapsInPlace() throws {
        let document = try ScriptFixture.document("batch.pen")
        _ = try run(
            "doc.replace('Cd101', { type: 'text', name: 'First', content: 'swapped' })",
            over: document
        )
        #expect(content(of: "Cd101", in: document) == "swapped")
    }

    @Test("doc.cp instantiates a reusable component as a ref")
    func copyInstantiates() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run("doc.cp('Cmp01', 'Crd01', { props: { 'common.name': 'Chip 2' } })", over: document)
        let id = try string("id", in: fields(of: run))
        #expect(document.nodes[id]?.common.name == "Chip 2")
        guard case let .ref(data) = document.nodes[id]?.kind else {
            Issue.record("copying a reusable component should make a ref")
            return
        }
        #expect(data.ref == "Cmp01")
    }

    @Test("doc.cp with each makes one copy per row")
    func copyEachMakesARowEach() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run(
            """
            doc.cp('Cd101', 'Crd01', {
              each: [{ 'common.name': 'Row A' }, { 'common.name': 'Row B' }]
            }).created.length;
            """,
            over: document
        )
        #expect(run.result == .int(2))
    }

    @Test("doc.mv moves the node to a new parent")
    func moveReparents() throws {
        let document = try ScriptFixture.document("batch.pen")
        _ = try run("doc.mv('Cd101', 'Brd01')", over: document)
        #expect(document.childIDs(of: "Brd01").contains("Cd101"))
    }

    @Test("doc.rm deletes the node and names it, with no revision for what is gone")
    func removeDeletes() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run("doc.rm('Cd101')", over: document)
        let report = try fields(of: run)
        #expect(report["id"] == .string("Cd101"))
        #expect(report["path"] == .string("Canvas/Cards/First"))
        #expect(report["nodeRevision"] == nil)
        #expect(document.nodes["Cd101"] == nil)
    }

    @Test("doc.rm with detach detaches the instances first")
    func removeDetaches() throws {
        let document = try ScriptFixture.document("batch.pen")
        _ = try run("doc.rm('Cmp01', { detach: true })", over: document)
        #expect(document.nodes["Cmp01"] == nil)
        if case .ref = document.nodes["Chi01"]?.kind {
            Issue.record("the instance should have been detached")
        }
    }

    // MARK: - override

    @Test("doc.override writes onto the instance and answers naming it")
    func overrideNamesTheInstance() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run("doc.override('Chi01/Label', { content: 'overridden' })", over: document)
        #expect(try fields(of: run)["id"] == .string("Chi01"))
    }

    @Test("doc.override unsets a key it is given")
    func overrideUnsets() throws {
        let document = try ScriptFixture.document("batch.pen")
        _ = try run("doc.override('Chi01/Label', { content: 'overridden' })", over: document)
        _ = try run("doc.override('Chi01/Label', null, { unset: ['content'] })", over: document)
        guard case let .ref(data) = document.nodes["Chi01"]?.kind else {
            Issue.record("Chi01 should still be an instance")
            return
        }
        #expect(data.descendants?.isEmpty != false)
    }

    // MARK: - vars and themes

    @Test("doc.vars.set adds a variable")
    func varsSetAdds() throws {
        let document = try ScriptFixture.document("batch.pen")
        _ = try run("doc.vars.set('brand', { type: 'color', value: '#FF6600' })", over: document)
        #expect(document.variables?["brand"]?.type == .color)
    }

    @Test("doc.vars.rm removes a variable nothing references")
    func varsRemoveRemoves() throws {
        let document = try ScriptFixture.document("batch.pen")
        _ = try run(
            """
            doc.vars.set('brand', { type: 'color', value: '#FF6600' });
            doc.vars.rm('brand');
            """,
            over: document
        )
        #expect(document.variables?["brand"] == nil)
    }

    @Test("doc.vars.rm refuses while a node still references the variable")
    func varsRemoveRefusesWhileReferenced() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run(
            """
            doc.vars.set('label', { type: 'string', value: 'chip' });
            doc.set('Ttl01', { 'kind.content': '$label' });
            try { doc.vars.rm('label'); } catch (e) { ({ code: e.code, message: e.message }); }
            """,
            over: document
        )
        let report = try fields(of: run)
        #expect(report["code"] == .string(ScriptErrorCode.variableInUse))
        #expect(try string("message", in: report).contains("force: true"))
        #expect(document.variables?["label"] != nil)
    }

    @Test("doc.vars.rm with force removes it anyway")
    func varsRemoveForced() throws {
        let document = try ScriptFixture.document("batch.pen")
        _ = try run(
            """
            doc.vars.set('label', { type: 'string', value: 'chip' });
            doc.set('Ttl01', { 'kind.content': '$label' });
            doc.vars.rm('label', { force: true });
            """,
            over: document
        )
        #expect(document.variables?["label"] == nil)
    }

    // MARK: - imports

    @Test("doc.imports.set adds an alias and changes the path of one that exists")
    func importsSetAddsAndChanges() throws {
        let document = try ScriptFixture.document("batch.pen")
        _ = try run("doc.imports.set('lib', './library.pen')", over: document)
        #expect(document.imports?["lib"] == "./library.pen")
        _ = try run("doc.imports.set('lib', './moved.pen')", over: document)
        #expect(document.imports?["lib"] == "./moved.pen")
    }

    @Test("doc.imports.set answers with the alias as its path, as the other table writes do")
    func importsSetReportsTheAlias() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run("doc.imports.set('lib', './library.pen')", over: document)
        let report = try fields(of: run)
        #expect(report["path"] == .string("lib"))
        #expect(report["id"] == nil)
        #expect(report["documentRevision"] == .string(document.documentRevision))
    }

    @Test("doc.imports.rm removes an alias nothing reaches into")
    func importsRemoveRemoves() throws {
        let document = try ScriptFixture.document("imports.pen")
        let run = try run("doc.imports.rm('icons')", over: document)
        #expect(document.imports?["icons"] == nil)
        #expect(try fields(of: run)["path"] == .string("icons"))
    }

    @Test("doc.imports.rm refuses while a ref still reaches into the namespace")
    func importsRemoveRefusesWhileReferenced() throws {
        let document = try ScriptFixture.document("imports.pen")
        let run = try run(
            "try { doc.imports.rm('V'); } catch (e) { ({ code: e.code, message: e.message }); }",
            over: document
        )
        let report = try fields(of: run)
        #expect(report["code"] == .string(ScriptErrorCode.importInUse))
        #expect(try string("message", in: report) == """
        Cannot remove V: 2 nodes reference it — Canvas/Button, Canvas/Title. Pass \
        `{ force: true }` to remove it anyway, leaving those references unresolved.
        """)
        #expect(document.imports?["V"] == "./library.pen")
    }

    @Test("doc.imports.rm with force removes it anyway")
    func importsRemoveForced() throws {
        let document = try ScriptFixture.document("imports.pen")
        _ = try run("doc.imports.rm('V', { force: true })", over: document)
        #expect(document.imports?["V"] == nil)
    }

    @Test("doc.themes.set declares an axis and doc.themes.rm takes it away")
    func themesSetAndRemove() throws {
        let document = try ScriptFixture.document("batch.pen")
        _ = try run("doc.themes.set('mode', ['light', 'dark'])", over: document)
        #expect(document.themes?["mode"] == ["light", "dark"])
        _ = try run("doc.themes.rm('mode')", over: document)
        #expect(document.themes?["mode"] == nil)
    }

    @Test("a document-level write names its subject and carries the revision")
    func documentWritesReportTheirSubject() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run("doc.themes.set('mode', ['light', 'dark'])", over: document)
        let report = try fields(of: run)
        #expect(report["path"] == .string("mode"))
        #expect(report["id"] == nil)
        #expect(report["documentRevision"] == .string(document.documentRevision))
    }

    // MARK: - Reads after writes

    @Test("a read after a write returns settled rects that reflect the write")
    func aReadAfterAWriteSettlesAgain() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run(
            """
            const before = doc.tree('Crd01').find(r => r.id === 'Cd101').rect.width;
            doc.set('Cd101', { 'kind.width': 250 });
            const after = doc.tree('Crd01').find(r => r.id === 'Cd101').rect.width;
            ({ before: before, after: after });
            """,
            over: document
        )
        #expect(run.result == .dictionary(["before": .int(100), "after": .int(250)]))
    }

    @Test("a read after a write sees the node's new revision")
    func aReadAfterAWriteSeesTheNewRevision() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run(
            """
            const written = doc.set('Ttl01', { 'kind.content': 'Hello' });
            doc.tree('Cnv01').find(r => r.id === 'Ttl01').rev === written.nodeRevision;
            """,
            over: document
        )
        #expect(run.result == .bool(true))
    }

    @Test("every write drops the settled tree, so the next read pays for a new one")
    func everyWriteInvalidatesTheCache() throws {
        let document = try ScriptFixture.document("batch.pen")
        let runner = ScriptRunner(
            document: document,
            remedy: .batch,
            diagnostics: [],
            recorder: nil,
            deadline: nil,
            sink: nil
        )
        let run = runner.run([.text(
            """
            doc.tree(); doc.tree();
            doc.set('Ttl01', { 'kind.content': 'Hello' });
            doc.tree();
            """,
            name: "<argv>"
        )])
        #expect(run.error == nil)
        #expect(runner.settled.settleCount == 2)
    }

    // MARK: - Atomicity

    @Test("a write that throws changes nothing, and a script that catches it continues")
    func aRefusedWriteChangesNothing() throws {
        let document = try ScriptFixture.document("batch.pen")
        let before = document.documentRevision
        let run = try run(
            """
            let caught = null;
            try {
              doc.set('Ttl01', { 'kind.notAProperty': 1 });
            } catch (e) { caught = e.code; }
            doc.set('Ttl01', { 'kind.content': 'after' });
            caught;
            """,
            over: document
        )
        #expect(run.result == .string("unknownProperty"))
        #expect(before != document.documentRevision, "the second write should have landed")
        #expect(content(of: "Ttl01", in: document) == "after")
    }

    @Test("a refused write leaves the document byte for byte what it was")
    func aRefusedWriteLeavesTheDocumentAlone() throws {
        let document = try ScriptFixture.document("batch.pen")
        let before = document.documentRevision
        let materialized = document.materialize()
        let run = ScriptHost.run(
            [.text("doc.set('Nope', { 'kind.content': 'x' })", name: "<argv>")],
            over: document
        )
        #expect(run.error?.code == "addressNotFound")
        #expect(document.documentRevision == before)
        #expect(document.materialize() == materialized)
    }

    // MARK: - Commit

    @Test("a run with writes and no error reports wrote")
    func aWritingRunReportsWrote() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run("doc.set('Ttl01', { 'kind.content': 'Hello' })", over: document)
        #expect(run.commit == .wrote)
        #expect(run.documentRevision == document.documentRevision)
    }

    @Test("a run that only reads reports unchanged")
    func aReadingRunReportsUnchanged() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = try run("doc.tree().length", over: document)
        #expect(run.commit == .unchanged)
    }

    @Test("an uncaught error after several writes reports rolledBack")
    func anUncaughtErrorRollsBack() throws {
        let document = try ScriptFixture.document("batch.pen")
        let run = ScriptHost.run(
            [.text(
                """
                doc.set('Ttl01', { 'kind.content': 'One' });
                doc.set('Cd101', { 'kind.width': 120 });
                doc.set('Nope', { 'kind.width': 1 });
                """,
                name: "<argv>"
            )],
            over: document
        )
        #expect(run.error?.code == "addressNotFound")
        #expect(run.commit == .rolledBack)
        #expect(run.events.count == 2, "the two writes that landed are still on the timeline")
    }
}
