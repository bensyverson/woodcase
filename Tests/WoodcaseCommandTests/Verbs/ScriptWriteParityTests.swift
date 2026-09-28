//
//  ScriptWriteParityTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
import WoodcaseScripting

/// Every write member of `doc` lands the same edit, and the same activity-log event, as
/// the verb it is named after.
///
/// The suite lives here for the same reason `ScriptReadParityTests` does: only a target
/// that can launch the real `woodcase` *and* call ``WoodcaseScripting/ScriptHost`` can
/// ask the question. One copy of the fixture is edited by the binary, another by a script
/// inside a ``Woodcase/PenFileTransaction``, and then the two files and the two logs are
/// compared. Comparing against a second in-process call would only prove that two callers
/// of ``Woodcase/BatchApplier`` agree, which they do by construction.
///
/// Ids are generated, so a verb that *creates* a node cannot produce the same bytes twice.
/// Those cases compare what does not depend on the id — the event's verb and the name
/// paths it touched — and the rest compare everything but the clock and the batch id.
@Suite("doc's writes match the verbs")
struct ScriptWriteParityTests {
    /// The word standing for the .pen file in a verb's argument list.
    ///
    /// A placeholder rather than "after the first word": `vars set <file> brand=…` puts
    /// the file two words in, and a rule that guessed would quietly test the wrong thing.
    private static let filePlaceholder = "<file>"

    /// One event, stripped of what two separate runs cannot share.
    private struct Trace: Equatable, CustomStringConvertible {
        /// The verb the log labels the event with.
        let op: String
        /// The name paths the event touched.
        let paths: [String]
        /// The node ids it touched, dropped for a verb that generates them.
        let nodes: [String]?
        /// The operations that undo it, dropped for a verb that generates ids.
        let inverse: [EditOperation]?

        var description: String {
            "\(op) \(paths)"
        }
    }

    /// The events a log holds, as traces.
    ///
    /// - Parameters:
    ///   - log: The log to read.
    ///   - identifying: Whether the ids and inverses are comparable, which they are not
    ///     for a verb that generates ids.
    /// - Returns: One trace per event, in log order.
    /// - Throws: Whatever the reader throws.
    private func traces(in log: ActivityLog, identifying: Bool) throws -> [Trace] {
        guard FileManager.default.fileExists(atPath: log.fileURL.path) else { return [] }
        return try ActivityReader(log: log).read().events.map {
            Trace(
                op: $0.op.rawValue,
                paths: $0.paths,
                nodes: identifying ? $0.nodes : nil,
                inverse: identifying ? $0.inverse : nil
            )
        }
    }

    /// Runs a script against a fixture inside a transaction, logging into its home.
    ///
    /// - Parameters:
    ///   - script: The JavaScript to run.
    ///   - fixture: The fixture to edit.
    /// - Returns: The log the run wrote into.
    /// - Throws: Whatever the transaction throws.
    @discardableResult
    private func runScript(_ script: String, on fixture: CommandFixture) async throws -> ActivityLog {
        let log = ActivityLog(home: fixture.home)
        let outcome = try await PenFileTransaction.run(
            at: fixture.file, identity: "ana", log: log
        ) { document, recorder in
            ScriptHost.run([.text(script, name: "<parity>")], over: document, recorder: recorder)
        }
        #expect(outcome.value.error == nil, "the script failed: \(outcome.value.error?.message ?? "")")
        return log
    }

    /// Runs a verb on one copy and the matching script on another, and compares both.
    ///
    /// - Parameters:
    ///   - verb: The command line, without the program name, with ``filePlaceholder``
    ///     where the .pen file goes.
    ///   - script: The JavaScript that should mean the same thing.
    ///   - identifying: Whether the *event* names ids two runs can share. `false` for a
    ///     verb whose event is about a node it just generated an id for.
    ///   - comparingFiles: Whether the two documents can be compared byte for byte.
    ///     `false` wherever the edit put a generated id in the file — which is a wider
    ///     set than `identifying`: `rm --detach` records an event about existing nodes
    ///     and *writes* a detached copy of the component's children with fresh ids.
    ///   - fixture: The .pen file both sides start from.
    private func parity(
        verb: [String],
        script: String,
        identifying: Bool = true,
        comparingFiles: Bool = true,
        fixture: String = "batch.pen"
    ) async throws {
        let commanded = try CommandFixture(fixture: fixture)
        let scripted = try CommandFixture(fixture: fixture)

        let arguments = verb.map { $0 == Self.filePlaceholder ? commanded.file.path : $0 }
        let run = try commanded.run(arguments + ["--as", "ana"])
        #expect(run.status == 0, "`woodcase \(verb.joined(separator: " "))` failed: \(run.stderr)")

        let log = try await runScript(script, on: scripted)

        let written = try traces(in: log, identifying: identifying)
        // Two empty logs are equal, and would make every case below pass for nothing.
        #expect(!written.isEmpty, "the script logged nothing for \(script)")
        #expect(
            try written == traces(in: ActivityLog(home: commanded.home), identifying: identifying),
            "the log differs for \(script)"
        )
        guard comparingFiles else { return }
        #expect(
            try Data(contentsOf: scripted.file) == Data(contentsOf: commanded.file),
            "the file differs for \(script)"
        )
    }

    /// Writes a subtree to a scratch file the verb can be pointed at.
    ///
    /// - Parameter json: The subtree as JSON.
    /// - Returns: The file's path.
    /// - Throws: Whatever writing it throws.
    private func subtreeFile(_ json: String) throws -> String {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodcase-parity-\(UUID().uuidString).json")
        try Data(json.utf8).write(to: url)
        return url.path
    }

    // MARK: - The node verbs

    @Test("doc.set writes what set writes")
    func setMatches() async throws {
        try await parity(
            verb: ["set", Self.filePlaceholder, "Ttl01", "kind.content=Hello"],
            script: "doc.set('Ttl01', { 'kind.content': 'Hello' })"
        )
    }

    @Test("an integer from a script is stored as the integer set stores")
    func anIntegerMatches() async throws {
        try await parity(
            verb: ["set", Self.filePlaceholder, "Ttl01", "kind.fontSize=18"],
            script: "doc.set('Ttl01', { 'kind.fontSize': 18 })"
        )
    }

    @Test("doc.mv moves what mv moves")
    func moveMatches() async throws {
        try await parity(
            verb: ["mv", Self.filePlaceholder, "Cd101", "Brd01"],
            script: "doc.mv('Cd101', 'Brd01')"
        )
    }

    @Test("doc.rm removes what rm removes")
    func removeMatches() async throws {
        try await parity(
            verb: ["rm", Self.filePlaceholder, "Cd101"],
            script: "doc.rm('Cd101')"
        )
    }

    @Test("doc.rm with detach matches rm --detach")
    func detachingRemoveMatches() async throws {
        try await parity(
            verb: ["rm", Self.filePlaceholder, "Cmp01", "--detach"],
            script: "doc.rm('Cmp01', { detach: true })",
            comparingFiles: false
        )
    }

    @Test("doc.override writes what override writes")
    func overrideMatches() async throws {
        try await parity(
            verb: ["override", Self.filePlaceholder, "Chi01/Label", "content=overridden"],
            script: "doc.override('Chi01/Label', { content: 'overridden' })"
        )
    }

    @Test("doc.add adds what add adds")
    func addMatches() async throws {
        let subtree = #"{"type":"frame","name":"Third","width":100,"height":60}"#
        try await parity(
            verb: ["add", Self.filePlaceholder, "Crd01", "-F", subtreeFile(subtree)],
            script: "doc.add('Crd01', \(subtree))",
            identifying: false,
            comparingFiles: false
        )
    }

    @Test("doc.cp copies what cp copies")
    func copyMatches() async throws {
        try await parity(
            verb: ["cp", Self.filePlaceholder, "Cmp01", "Crd01", "common.name=Chip 2"],
            script: "doc.cp('Cmp01', 'Crd01', { props: { 'common.name': 'Chip 2' } })",
            identifying: false,
            comparingFiles: false
        )
    }

    @Test("doc.replace replaces what replace replaces")
    func replaceMatches() async throws {
        let subtree = #"{"type":"text","name":"First","content":"swapped"}"#
        try await parity(
            verb: ["replace", Self.filePlaceholder, "Cd101", "-F", subtreeFile(subtree)],
            script: "doc.replace('Cd101', \(subtree))",
            identifying: false,
            comparingFiles: false
        )
    }

    // MARK: - The document verbs

    @Test("doc.vars.set writes what vars set writes")
    func variableMatches() async throws {
        try await parity(
            verb: ["vars", "set", Self.filePlaceholder, "brand=#FF6600"],
            script: "doc.vars.set('brand', { type: 'color', value: '#FF6600' })"
        )
    }

    @Test("doc.themes.set declares the axis vars axis add declares")
    func themeAxisMatches() async throws {
        try await parity(
            verb: ["vars", "axis", "add", Self.filePlaceholder, "mode=light,dark"],
            script: "doc.themes.set('mode', ['light', 'dark'])"
        )
    }

    /// Criterion NmZ.
    @Test("doc.imports.set writes what imports set writes")
    func importMatches() async throws {
        try await parity(
            verb: ["imports", "set", Self.filePlaceholder, "lib", "./library.pen"],
            script: "doc.imports.set('lib', './library.pen')"
        )
    }

    /// Criterion NmZ.
    @Test("doc.imports.rm removes what imports rm removes")
    func importRemovalMatches() async throws {
        try await parity(
            verb: ["imports", "rm", Self.filePlaceholder, "icons"],
            script: "doc.imports.rm('icons')",
            fixture: "imports.pen"
        )
    }

    @Test("doc.vars.rm removes what vars rm removes")
    func variableRemovalMatches() async throws {
        let commanded = try CommandFixture(fixture: "batch.pen")
        let scripted = try CommandFixture(fixture: "batch.pen")
        for fixture in [commanded, scripted] {
            let seeded = try fixture.run("vars", "set", fixture.file.path, "brand=#FF6600", "--as", "ana")
            #expect(seeded.status == 0, "\(seeded.stderr)")
        }
        let removed = try commanded.run("vars", "rm", commanded.file.path, "brand", "--as", "ana")
        #expect(removed.status == 0, "\(removed.stderr)")

        let log = try await runScript("doc.vars.rm('brand')", on: scripted)
        #expect(
            try traces(in: log, identifying: true)
                == traces(in: ActivityLog(home: commanded.home), identifying: true)
        )
        #expect(try Data(contentsOf: scripted.file) == Data(contentsOf: commanded.file))
    }
}
