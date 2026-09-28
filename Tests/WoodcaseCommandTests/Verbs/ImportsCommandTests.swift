//
//  ImportsCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase imports`, driven as an agent drives it: the binary, its bytes and its
/// exit code.
///
/// The verb pair is `vars`' shape over the document's other name table, so the suite
/// asks the same questions of it — a listing, an add, a change, a removal, the refusal
/// while something still reaches into the namespace, and the `import` event each write
/// leaves in the log.
struct ImportsCommandTests {
    /// The `.pen` file's JSON, as written back to disk.
    private func document(_ url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    }

    /// The `imports` table of a written `.pen` file.
    private func imports(in url: URL) -> [String: String] {
        document(url)["imports"] as? [String: String] ?? [:]
    }

    /// The decoded `--json` object a run printed.
    private func json(_ run: CommandRun) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(run.stdout.utf8))) as? [String: Any] ?? [:]
    }

    // MARK: - Listing

    @Test("A bare `imports <file>` lists each alias, its reference count and its path")
    func listsImports() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let run = try fixture.run("imports", fixture.file.path)
        #expect(run.status == 0)
        #expect(run.stdout == """
        imports
          V      2 refs  ./library.pen
          icons  0 refs  ../shared/icons.pen

        """)
    }

    @Test("`--json` carries the aliases, their counts and the document revision")
    func listsAsJSON() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let run = try fixture.run("imports", fixture.file.path, "--json")
        #expect(run.status == 0)
        let object = json(run)
        #expect(object["revision"] is String)
        let rows = try #require(object["imports"] as? [[String: Any]])
        #expect(rows.map { $0["alias"] as? String } == ["V", "icons"])
        #expect(rows[0]["path"] as? String == "./library.pen")
        #expect(rows[0]["references"] as? Int == 2)
    }

    @Test("A document with no imports says so and exits 0")
    func listsNothing() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("imports", fixture.file.path)
        #expect(run.status == 0)
        #expect(run.stdout == "No imports in batch.pen.\n")
    }

    @Test("A missing file is a target failure")
    func missingFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let run = try fixture.run("imports", fixture.root.appendingPathComponent("nope.pen").path)
        #expect(run.status == 4)
        #expect(run.stderr.contains("no such file"))
    }

    // MARK: - set

    /// Criterion NmZ.
    @Test("Setting a new alias adds the import and prints the revision")
    func setAddsImport() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(
            "imports", "set", fixture.file.path, "lib", "./library.pen", "--as", "ana"
        )
        #expect(run.status == 0)
        #expect(run.stdout.contains("lib  0 refs  ./library.pen"))
        #expect(run.stdout.contains("revision "))
        #expect(imports(in: fixture.file) == ["lib": "./library.pen"])
    }

    /// Criterion NmZ.
    @Test("Setting an alias the document already has changes its path in place")
    func setUpdatesImport() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let run = try fixture.run(
            "imports", "set", fixture.file.path, "V", "./moved.pen", "--as", "ana"
        )
        #expect(run.status == 0)
        #expect(run.stdout.contains("V  2 refs  ./moved.pen"))
        #expect(imports(in: fixture.file)["V"] == "./moved.pen")
        #expect(imports(in: fixture.file)["icons"] == "../shared/icons.pen")
    }

    /// Criterion NmZ.
    @Test("A set is logged as an `import` event attributed to the writer")
    func setLogsAnImportEvent() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        _ = try fixture.run("imports", "set", fixture.file.path, "lib", "./library.pen", "--as", "ana")
        let log = try String(contentsOf: fixture.activityLog, encoding: .utf8)
        #expect(log.contains("\"op\":\"import\""))
        #expect(log.contains("ana"))
    }

    @Test("`--dry-run` writes nothing and says so")
    func setRehearses() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try String(contentsOf: fixture.file, encoding: .utf8)
        let run = try fixture.run(
            "imports", "set", fixture.file.path, "lib", "./library.pen", "--dry-run", "--as", "ana"
        )
        #expect(run.status == 0)
        #expect(run.stdout.contains(DryRunOption.marker))
        #expect(!run.stdout.contains("revision "))
        #expect(try String(contentsOf: fixture.file, encoding: .utf8) == before)
    }

    // MARK: - rm

    /// Criterion NmZ.
    @Test("An alias nothing reaches into is removed without a flag")
    func removeUnreferenced() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let run = try fixture.run("imports", "rm", fixture.file.path, "icons", "--as", "ana")
        #expect(run.status == 0)
        #expect(run.stdout.contains("Removed icons (../shared/icons.pen)."))
        #expect(run.stdout.contains("revision "))
        #expect(imports(in: fixture.file)["icons"] == nil)
        let log = try String(contentsOf: fixture.activityLog, encoding: .utf8)
        #expect(log.contains("\"op\":\"import\""))
    }

    /// Criterion OLO.
    @Test("Removing an alias a ref still uses is refused, naming the instances")
    func removeRefusesWhileReferenced() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let run = try fixture.run("imports", "rm", fixture.file.path, "V", "--as", "ana")
        #expect(run.status == 2)
        #expect(run.stderr.contains("""
        Cannot remove V: 2 nodes reference it — Canvas/Button, Canvas/Title. Pass --force to \
        remove it anyway, leaving those references unresolved.
        """))
        #expect(imports(in: fixture.file)["V"] == "./library.pen")
    }

    /// Criterion OLO.
    @Test("`--force` removes a referenced alias anyway")
    func removeForced() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let run = try fixture.run("imports", "rm", fixture.file.path, "V", "--force", "--as", "ana")
        #expect(run.status == 0)
        #expect(imports(in: fixture.file)["V"] == nil)
    }

    @Test("Removing an alias the document does not have is a usage error naming it")
    func removeUnknownAlias() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let run = try fixture.run("imports", "rm", fixture.file.path, "nope", "--as", "ana")
        #expect(run.status == 2)
        #expect(run.stderr.contains("nope"))
        #expect(run.stderr.contains("woodcase imports"))
    }

    /// Criterion OLO.
    @Test("`--force --dry-run` rehearses the forced removal and writes nothing")
    func removeForcedRehearsal() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let before = try String(contentsOf: fixture.file, encoding: .utf8)
        let run = try fixture.run(
            "imports", "rm", fixture.file.path, "V", "--force", "--dry-run", "--as", "ana"
        )
        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout.contains(DryRunOption.marker))
        #expect(run.stdout.contains("Removed V (./library.pen)."))
        #expect(!run.stdout.contains("revision "))
        #expect(try String(contentsOf: fixture.file, encoding: .utf8) == before)
    }

    // MARK: - undo

    /// Criterion NmZ.
    @Test("`undo` reverses an import event, putting the alias back with its old path")
    func undoReversesAnImportWrite() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        let removed = try fixture.run("imports", "rm", fixture.file.path, "icons", "--as", "ana")
        #expect(removed.status == 0, "\(removed.stderr)")
        #expect(imports(in: fixture.file)["icons"] == nil)

        let undone = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(undone.status == 0, "\(undone.stderr)")
        #expect(imports(in: fixture.file)["icons"] == "../shared/icons.pen")
    }

    @Test("`undo` takes back a changed path, restoring the one it replaced")
    func undoReversesAChangedPath() throws {
        let fixture = try CommandFixture(fixture: "imports.pen")
        _ = try fixture.run("imports", "set", fixture.file.path, "V", "./moved.pen", "--as", "ana")
        let undone = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(undone.status == 0, "\(undone.stderr)")
        #expect(imports(in: fixture.file)["V"] == "./library.pen")
    }
}
