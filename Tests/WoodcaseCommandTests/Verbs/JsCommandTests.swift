//
//  JsCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase js` — a JavaScript program over the document, in one transaction.
///
/// Drives the built binary, because the whole contract is what a shell sees: the
/// transcript on stdout, the refusal on stderr, the exit status, and the file's bytes
/// afterwards.
@Suite("woodcase js")
struct JsCommandTests {
    /// Writes a script beside the fixture and answers with its path.
    private func script(_ body: String, named name: String, in fixture: CommandFixture) throws -> String {
        let url = fixture.root.appendingPathComponent(name)
        try Data(body.utf8).write(to: url)
        return url.path
    }

    /// The script the plan document's "What ships" transcript shows, verbatim.
    ///
    /// Kept here so the criterion *the transcript runs as written* is a test and not a
    /// claim: if the doc and this string drift, the row counts below stop matching.
    static let planTranscriptScript = """
    const section = doc.get('banking-home/transactions-section');
    const template = doc.tree('banking-home/transactions-section')
      .filter(r => r.type === 'ref' && r.depth === 1)[0];

    for (const [i, name] of ['Groceries', 'Transit', 'Coffee'].entries()) {
      doc.cp(template.id, section.node.id, {
        props: {
          'common.name': `row-${name}`,
          'info/merchant/kind.content': name,
          'amount-wrap/amount/kind.content': `$${(i + 1) * 4}.00`
        }
      });
    }

    const tall = doc.tree('banking-home/transactions-section')
      .filter(r => r.depth === 1 && r.rect.height > 64);
    if (tall.length) throw new Error(`${tall.length} rows overflow: ${tall.map(r => r.address).join(', ')}`);

    doc.rm(template.id);
    doc.lint().length
    """

    // MARK: - The transcript

    @Test("The plan document's script runs against banking.pen and prints its rows, result and revision")
    func planTranscriptRuns() throws {
        let fixture = try CommandFixture(fixture: "banking.pen")
        let path = try script(Self.planTranscriptScript, named: "rows.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana")

        #expect(run.status == 0)
        let lines = run.stdoutLines
        // Three copies, the template removed, then the two closing rows. Each write row
        // leads with the member that made it, padded so the paths line up.
        try #require(lines.count == 6)
        #expect(lines[0].hasPrefix("cp           banking-home/transactions-section/row-Groceries  "))
        #expect(lines[1].hasPrefix("cp           banking-home/transactions-section/row-Transit  "))
        #expect(lines[2].hasPrefix("cp           banking-home/transactions-section/row-Coffee  "))
        #expect(lines[3].hasPrefix("rm           banking-home/transactions-section/t1  "))
        #expect(lines[4].hasPrefix("result  "))

        // The document really moved, the revision printed is the file's own, and the
        // overrides the copies carried landed on the descendants they named.
        let document = try EditableDocument(from: PenParser.parse(contentsOf: fixture.file))
        #expect(lines[5] == "document  \(document.documentRevision)")
        let merchants = document.nodes.values
            .compactMap { node -> String? in
                guard case let .ref(data) = node.kind,
                      node.common.name?.hasPrefix("row-") == true,
                      case let .string(text) = data.descendants?["vpvCO"]?.properties["content"]
                else { return nil }
                return text
            }
            .sorted()
        #expect(merchants == ["Coffee", "Groceries", "Transit"])
    }

    @Test("A created subtree's row carries (+N) for the descendants that came with it")
    func aCreatedRowCountsItsDescendants() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(
            "doc.cp('Canvas/Cards', 'Board')", named: "copy.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path)

        #expect(run.status == 0)
        // Cards holds First and Second, so the copy brings two descendants with it.
        #expect(try #require(run.stdoutLines.first).hasSuffix("  (+2)"))
    }

    @Test("A write that diverged from what was asked prints the sentence under its row")
    func divergencesAreIndentedUnderTheirRow() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        // A number written to a property that takes text is the everyday divergence.
        let path = try script(
            "doc.set('Canvas/Title', { 'kind.content': 42 })", named: "coerce.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path)

        #expect(run.status == 0)
        let lines = run.stdoutLines
        try #require(lines.count >= 2)
        #expect(lines[0] == "set          Canvas/Title  Ttl01")
        // Indented past the member gutter, so the sentence sits under the path it is
        // about rather than under the member column.
        #expect(lines[1].hasPrefix("             kind.content stored the number 42 as the text"))
    }

    @Test("Each write row leads with the doc member that made it")
    func everyRowNamesItsMember() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        // A copy and two overrides of the same instance: without the member column the
        // three rows would name the same instance and read identically.
        let path = try script(
            """
            doc.cp('Chip', 'Board', { props: { 'common.name': 'Chip 2' } });
            doc.override('Board/Chip 2/Label', { content: 'one' });
            doc.override('Board/Chip 2/Label', { content: 'two' });
            doc.vars.set('brand', { type: 'color', value: '#FF6600' });
            """,
            named: "rows.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana")

        #expect(run.status == 0)
        let lines = run.stdoutLines
        try #require(lines.count == 6)
        #expect(lines[0].hasPrefix("cp           Board/Chip 2  "))
        #expect(lines[1].hasPrefix("override     Board/Chip 2  "))
        #expect(lines[2] == lines[1])
        #expect(lines[3] == "vars.set     brand")
    }

    @Test("A read-only script prints only its result and the revision it read at")
    func aReadOnlyScriptIsQuiet() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let path = try script("doc.tree('Canvas').length", named: "count.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path)

        #expect(run.status == 0)
        try #require(run.stdoutLines.count == 2)
        #expect(run.stdoutLines[0] == "result  5")
        #expect(run.stdoutLines[1].hasPrefix("document  "))
        try #expect(Data(contentsOf: fixture.file) == before)
    }

    @Test("A script whose last statement is not an expression prints no result line")
    func noCompletionValuePrintsNoResult() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script("const n = doc.tree().length;", named: "quiet.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path)

        #expect(run.status == 0)
        #expect(!run.stdout.contains("result  "))
        #expect(run.stdoutLines.count == 1)
    }

    // MARK: - Sources

    @Test("A function defined in the first -F file is callable from the second")
    func helpersPrecedeTheRun() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let helpers = try script(
            "function titles() { return doc.tree().filter(r => r.type === 'text'); }",
            named: "helpers.js", in: fixture
        )
        let body = try script("titles().length", named: "run.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", helpers, "-F", body)

        #expect(run.status == 0)
        #expect(run.stdoutLines.first == "result  2")
    }

    @Test("An error in the second -F file is reported with that file's name and line")
    func anErrorNamesItsOwnSource() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let helpers = try script(
            "function widths() { return doc.tree().map(r => r.rect.width); }\n",
            named: "helpers.js", in: fixture
        )
        let body = try script(
            "const w = widths();\nthrow new Error('too wide: ' + w.length);\n",
            named: "run.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", helpers, "-F", body)

        #expect(run.status == ExitCode.cleanNegative.rawValue)
        #expect(run.stderr.contains("run.js:2:"))
        #expect(!run.stderr.contains("helpers.js"))
        #expect(run.stderr.contains("too wide: 9"))
        #expect(run.stderr.contains("throw new Error("))
    }

    @Test("-F - reads the script from standard input")
    func stdinIsASource() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            ["js", fixture.file.path, "-F", "-"],
            stdin: Data("doc.tree('Canvas').length".utf8)
        )

        #expect(run.status == 0)
        #expect(run.stdoutLines.first == "result  5")
    }

    @Test("A failure in a script read from standard input is named <stdin>")
    func stdinIsNamedInAFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(
            ["js", fixture.file.path, "-F", "-"],
            stdin: Data("throw new Error('no')".utf8)
        )

        #expect(run.status == ExitCode.cleanNegative.rawValue)
        #expect(run.stderr.contains("<stdin>:1:"))
    }

    @Test("Standard input may only be named once")
    func standardInputIsNamedOnce() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run(["js", fixture.file.path, "-F", "-", "-F", "-"])

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("standard input"))
    }

    @Test("js with no -F at all is a usage error naming the flag")
    func aScriptIsRequired() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")

        let run = try fixture.run("js", fixture.file.path)

        #expect(run.status == ExitCode.usage.rawValue)
        #expect(run.stderr.contains("js needs a script"))
    }

    // MARK: - Guards

    @Test("A stale document pin refuses before the script runs, naming the writer")
    func aStaleGuardRefusesBeforeTheScript() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let original = try EditableDocument(
            from: PenParser.parse(contentsOf: fixture.file)
        ).documentRevision
        let moved = try fixture.run(
            "set", fixture.file.path, "Canvas/Title", "kind.content=Moved", "--as", "bob"
        )
        #expect(moved.status == 0)

        let path = try script(
            "console.log('the script ran'); doc.set('Canvas/Title', { 'kind.content': 'Mine' })",
            named: "late.js", in: fixture
        )
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run(
            "js", fixture.file.path, "-F", path, "--guard", original, "--as", "ana"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(run.stderr.contains("bob"))
        // The refusal is at the transaction's door: the script never got to speak.
        #expect(!run.stdout.contains("the script ran"))
        try #expect(Data(contentsOf: fixture.file) == before)
    }

    @Test("A pin that still holds lets the script through")
    func acurrentGuardPasses() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let revision = try EditableDocument(
            from: PenParser.parse(contentsOf: fixture.file)
        ).documentRevision
        let path = try script(
            "doc.set('Canvas/Title', { 'kind.content': 'Mine' })", named: "ok.js", in: fixture
        )

        let run = try fixture.run(
            "js", fixture.file.path, "-F", path, "--guard", revision, "--as", "ana"
        )

        #expect(run.status == 0)
    }

    // MARK: - Rolling back

    @Test("An uncaught error exits 1, writes nothing, and says so")
    func anUncaughtErrorWritesNothing() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let path = try script(
            """
            doc.set('Canvas/Title', { 'kind.content': 'Half' });
            throw new Error('changed my mind');
            """,
            named: "abort.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana")

        #expect(run.status == ExitCode.cleanNegative.rawValue)
        #expect(run.stderr.contains("changed my mind"))
        #expect(run.stderr.contains("nothing was written"))
        try #expect(Data(contentsOf: fixture.file) == before)
        #expect(!FileManager.default.fileExists(atPath: fixture.activityLog.path))
    }

    @Test("A refusal from the editing layer keeps the sentence the verb would have printed")
    func aRefusalKeepsItsRemedy() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script("doc.set('Nowhere', { 'kind.content': 'x' })", named: "miss.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path)

        #expect(run.status == ExitCode.cleanNegative.rawValue)
        #expect(run.stderr.contains("Nowhere"))
    }

    @Test("A caught refusal leaves the document consistent and the run commits")
    func aCaughtRefusalCarriesOn() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(
            """
            try { doc.set('Nowhere', { 'kind.content': 'x' }); } catch (e) { console.log('caught ' + e.code); }
            doc.set('Canvas/Title', { 'kind.content': 'Kept' });
            """,
            named: "catch.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana")

        #expect(run.status == 0)
        #expect(run.stdout.contains("caught addressNotFound"))
        let document = try EditableDocument(from: PenParser.parse(contentsOf: fixture.file))
        guard case let .text(data) = document.node(id: "Ttl01")?.kind else {
            Issue.record("Canvas/Title is not a text node")
            return
        }
        #expect(data.content?.literalValue == "Kept")
    }

    // MARK: - Exit codes

    @Test("A source that will not parse exits 2, naming the source, line, column and message")
    func aSyntaxErrorIsAUsageError() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script("const x = ;\n", named: "broken.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path)

        #expect(run.status == ExitCode.usage.rawValue)
        // JavaScriptCore records a line for a parse failure and, for this one, no column.
        #expect(run.stderr.contains("broken.js:1  "))
        #expect(run.stderr.contains("  const x = ;"))
    }

    @Test("A refusal the prelude raised names doc's members and locates nothing that is not there")
    func apreludeRefusalNamesNoPhantomLine() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script("doc.setProps('Canvas/Title', {})", named: "typo.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path)

        #expect(run.status == ExitCode.cleanNegative.rawValue)
        #expect(run.stderr.contains("doc has no setProps"))
        // The throw was raised in the prelude, so there is no line of typo.js to point at
        // — and the report points at none, rather than at a line the file does not have.
        #expect(!run.stderr.contains("typo.js:"))
    }

    @Test("A -F path that cannot be read exits 4, as every other body does")
    func anUnreadableScriptIsATargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let missing = fixture.root.appendingPathComponent("nowhere.js").path

        let run = try fixture.run("js", fixture.file.path, "-F", missing)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("nowhere.js could not be read"))
        // The message names the path once, not once as a location and again as prose.
        #expect(run.stderr.components(separatedBy: "nowhere.js").count == 2)
    }

    @Test("A file that is not a .pen document exits 4 before the script runs")
    func anUnreadableDocumentIsATargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let broken = fixture.root.appendingPathComponent("broken.pen")
        try Data("this is not json".utf8).write(to: broken)
        let path = try script("console.log('ran')", named: "hello.js", in: fixture)

        let run = try fixture.run("js", broken.path, "-F", path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(!run.stdout.contains("ran"))
    }

    @Test("A $WOODCASE_HOME that is a file, not a directory, is an environment error, exit 5")
    func anUnusableLogIsAnEnvironmentError() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let notADirectory = fixture.root.appendingPathComponent("home-as-file")
        try Data("x".utf8).write(to: notADirectory)
        let path = try script(
            "doc.set('Canvas/Title', { 'kind.content': 'Logged' })", named: "write.js", in: fixture
        )

        let run = try fixture.run(
            ["js", fixture.file.path, "-F", path, "--as", "ana"],
            environment: [ActivityLog.homeEnvironmentVariable: notADirectory.path]
        )

        #expect(run.status == ExitCode.environment.rawValue)
        #expect(run.stderr.contains("WOODCASE_HOME"))
    }

    // MARK: - Dry run

    @Test("--dry-run runs the script, writes nothing, and reports the findings it would introduce")
    func dryRunPreviewsTheFindings() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let path = try script(
            "console.log('measuring'); doc.set('Canvas/Cards/First', { 'kind.width': 900 })",
            named: "wide.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--dry-run", "--as", "ana")

        #expect(run.status == 0)
        #expect(run.stdoutLines.first == DryRunOption.marker)
        #expect(run.stdout.contains("measuring"))
        #expect(run.stdout.contains("warning clipped  Canvas/Cards/First (Cd101)"))
        #expect(run.stdout.contains("warning clipped  Canvas/Cards/Second (Cd201)"))
        // A rehearsal made no revision, so it names none — as every other verb's does.
        #expect(!run.stdout.contains("document  "))
        try #expect(Data(contentsOf: fixture.file) == before)
        #expect(!FileManager.default.fileExists(atPath: fixture.activityLog.path))
    }

    @Test("A dry run refused by a guard exits 3 and prints no marker")
    func aRefusedGuardBeatsTheRehearsal() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let stale = String(repeating: "0", count: 16)
        let path = try script("doc.tree().length", named: "read.js", in: fixture)

        let run = try fixture.run(
            "js", fixture.file.path, "-F", path, "--guard", stale, "--dry-run"
        )

        #expect(run.status == ExitCode.conflict.rawValue)
        #expect(!run.stdout.contains(DryRunOption.marker))
    }

    // MARK: - The log

    @Test("Every write the script made is one activity event, under one transaction")
    func theLogRecordsTheWholeRun() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(
            """
            doc.set('Canvas/Title', { 'kind.content': 'One' });
            doc.set('Canvas/Cards/First', { 'common.name': 'Primo' });
            """,
            named: "two.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana")
        #expect(run.status == 0)

        let activity = try fixture.run("activity", "--json")
        #expect(activity.status == 0)
        let events = activity.stdoutLines.filter { !$0.isEmpty }
        #expect(events.count == 2)
        #expect(events.allSatisfy { $0.contains("\"identity\":\"ana\"") })
    }

    @Test("A script that writes and writes back leaves the file unchanged and says so")
    func writesThatCancelOutReportUnchanged() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let before = try Data(contentsOf: fixture.file)
        let path = try script(
            """
            const was = doc.get('Canvas/Title').node.content;
            doc.set('Canvas/Title', { 'kind.content': 'Elsewhere' });
            doc.set('Canvas/Title', { 'kind.content': was });
            """,
            named: "loop.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana", "--json")

        #expect(run.status == 0)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any]
        )
        #expect(object["commit"] as? String == "unchanged")
        try #expect(Data(contentsOf: fixture.file) == before)
    }
}
