//
//  ImportsParityTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// An `{"op":"import"}` line must do what `imports set` does.
///
/// The batch route is the third of the three the import table gained, and it is the one
/// with the smallest surface: it adds or changes, and — like `var` — it deliberately
/// carries no removal, because an optional payload would turn a dropped field into a
/// silent delete. Both halves are asserted here, the second by writing a removal-shaped
/// line and watching the grammar refuse it.
@MainActor
@Suite("apply / imports parity")
struct ImportsParityTests {
    /// Writes a batch to a file inside the fixture and answers with its path.
    private func writeOps(_ jsonl: String, into fixture: CommandFixture) throws -> String {
        let url = fixture.root.appendingPathComponent("ops-\(UUID().uuidString).jsonl")
        try jsonl.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// The `imports` table of a written `.pen` file.
    private func imports(in url: URL) -> [String: String] {
        guard let data = try? Data(contentsOf: url),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return [:] }
        return object["imports"] as? [String: String] ?? [:]
    }

    /// Criterion NmZ.
    @Test("An import line adds the alias the verb adds, and logs the same event")
    func batchImportAddsWhatTheVerbAdds() throws {
        let batched = try CommandFixture(fixture: "batch.pen")
        let commanded = try CommandFixture(fixture: "batch.pen")
        let opsPath = try writeOps(
            #"{"op":"import","alias":"lib","path":"./library.pen"}"#,
            into: batched
        )

        let applied = try batched.run("apply", batched.file.path, "-F", opsPath, "--as", "ana")
        #expect(applied.status == 0, "apply failed: \(applied.stdout)\(applied.stderr)")
        let set = try commanded.run(
            "imports", "set", commanded.file.path, "lib", "./library.pen", "--as", "ana"
        )
        #expect(set.status == 0, "\(set.stderr)")

        #expect(imports(in: batched.file) == imports(in: commanded.file))
        #expect(imports(in: batched.file) == ["lib": "./library.pen"])
        let log = try String(contentsOf: batched.activityLog, encoding: .utf8)
        #expect(log.contains("\"op\":\"import\""))
    }

    /// Criterion NmZ.
    @Test("An import line whose alias already exists changes the path rather than failing")
    func batchImportChangesAnExistingAlias() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let opsPath = try writeOps(
            #"{"op":"import","alias":"V","path":"./moved.pen"}"#,
            into: fixture
        )
        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath, "--as", "ana")
        #expect(run.status == 0, "apply failed: \(run.stdout)\(run.stderr)")
        #expect(imports(in: fixture.file)["V"] == "./moved.pen")
    }

    @Test("The grammar carries no removal, so a line without a path is refused")
    func batchHasNoImportRemoval() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let opsPath = try writeOps(#"{"op":"import","alias":"icons"}"#, into: fixture)
        let run = try fixture.run("apply", fixture.file.path, "-F", opsPath, "--as", "ana")
        #expect(run.status != 0)
        #expect(imports(in: fixture.file)["icons"] == "../shared/icons.pen")
    }

    @Test("`apply --help` prints the import line, because the grammar is one source of truth")
    func theGrammarTeachesTheImportLine() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let run = try fixture.run("apply", "--help")
        #expect(run.stdout.contains(#"{"op":"import","alias":ALIAS,"path":PATH}"#))
    }
}
