//
//  JsOutputTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// What `woodcase js` puts on which stream, and that `--json` says the same thing.
///
/// The transcript is the verb's whole answer, so the split between the streams and the
/// order inside stdout are the contract — not decoration. Both forms are rendered from
/// one `ScriptRun`, and these runs are what proves the two never say different things.
@Suite("woodcase js output")
struct JsOutputTests {
    /// Writes a script beside the fixture and answers with its path.
    private func script(_ body: String, named name: String, in fixture: CommandFixture) throws -> String {
        let url = fixture.root.appendingPathComponent(name)
        try Data(body.utf8).write(to: url)
        return url.path
    }

    /// A script that prints on both sides of two writes, so the ordering is visible.
    private static let chatty = """
    console.log('before');
    doc.set('Canvas/Title', { 'kind.content': 'One' });
    console.log('between');
    doc.set('Canvas/Cards/First', { 'common.name': 'Primo' });
    console.warn('a warning');
    console.error('an error');
    console.log('after');
    ({ titles: doc.tree().filter(r => r.type === 'text').length })
    """

    // MARK: - The two streams

    @Test("console.log lands on stdout between the write rows it was printed between")
    func logLinesInterleaveWithWrites() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(Self.chatty, named: "chatty.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana")

        #expect(run.status == 0)
        let lines = run.stdoutLines
        let before = try #require(lines.firstIndex(of: "before"))
        let title = try #require(lines.firstIndex { $0.contains("Ttl01") })
        let between = try #require(lines.firstIndex(of: "between"))
        let card = try #require(lines.firstIndex { $0.contains("Cd101") })
        let after = try #require(lines.firstIndex(of: "after"))
        #expect(before < title)
        #expect(title < between)
        #expect(between < card)
        #expect(card < after)
    }

    @Test("console.warn and console.error go to stderr, and never to stdout")
    func warnAndErrorGoToStandardError() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(Self.chatty, named: "chatty.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana")

        #expect(run.stderr.contains("a warning"))
        #expect(run.stderr.contains("an error"))
        #expect(!run.stdout.contains("a warning"))
        #expect(!run.stdout.contains("an error"))
    }

    @Test("The transcript ends with result and then document, in that order")
    func theTailClosesTheTranscript() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(Self.chatty, named: "chatty.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana")

        let lines = run.stdoutLines
        try #require(lines.count >= 2)
        #expect(lines[lines.count - 2] == #"result  {"titles":2}"#)
        #expect(lines[lines.count - 1].hasPrefix("document  "))
    }

    @Test("--json prints nothing live: one object and nothing else on stdout")
    func jsonPrintsOnlyTheObject() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(Self.chatty, named: "chatty.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana", "--json")

        #expect(run.status == 0)
        #expect(run.stdout.hasPrefix("{"))
        _ = try #require(JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any])
        #expect(!run.stdout.contains("\nbefore\n"))
        #expect(run.stderr.isEmpty)
    }

    // MARK: - One value, two forms

    @Test("Everything the text form printed is in the JSON form too")
    func theTwoFormsAgree() throws {
        let text = try CommandFixture(fixture: "batch.pen")
        let textPath = try script(Self.chatty, named: "chatty.js", in: text)
        let textRun = try text.run("js", text.file.path, "-F", textPath, "--as", "ana")

        let json = try CommandFixture(fixture: "batch.pen")
        let jsonPath = try script(Self.chatty, named: "chatty.js", in: json)
        let jsonRun = try json.run("js", json.file.path, "-F", jsonPath, "--as", "ana", "--json")

        #expect(textRun.status == jsonRun.status)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(jsonRun.stdout.utf8)) as? [String: Any]
        )

        // The revision the text form ends with is the JSON's documentRevision.
        let documentRow = try #require(textRun.stdoutLines.last)
        #expect(try documentRow == "document  \(#require(object["documentRevision"] as? String))")

        // The result row is the JSON's result, compactly encoded.
        #expect(object["result"] as? [String: Any] != nil)
        #expect(textRun.stdoutLines.contains(#"result  {"titles":2}"#))

        // Every event the two streams carried is one entry of `events`, in order.
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.map { $0["event"] as? String } == [
            "log", "write", "log", "write", "log", "log", "log",
        ])
        #expect(events.compactMap { $0["text"] as? String } == [
            "before", "between", "a warning", "an error", "after",
        ])
        #expect(events.compactMap { $0["level"] as? String } == [
            "log", "log", "warn", "error", "log",
        ])
        let writes = events.compactMap { $0["write"] as? [String: Any] }
        #expect(writes.compactMap { $0["id"] as? String } == ["Ttl01", "Cd101"])
        // Every write event names the member that made it, and the text row leads with
        // the same word — so a reader of either form knows which verb wrote which row.
        #expect(events.compactMap { $0["member"] as? String } == ["set", "set"])
        for (event, write) in zip(events.filter { $0["event"] as? String == "write" }, writes) {
            let member = try #require(event["member"] as? String)
            let path = try #require(write["path"] as? String)
            let id = try #require(write["id"] as? String)
            #expect(textRun.stdoutLines.contains {
                $0.hasPrefix("\(member) ") && $0.hasSuffix("\(path)  \(id)")
            })
        }

        #expect(object["commit"] as? String == "wrote")
        #expect(object["error"] == nil)
        #expect(object["dryRun"] == nil)
        #expect(object["lint"] == nil)
    }

    @Test("A failed run's JSON carries the error the text form printed on stderr")
    func failuresCrossToJSONToo() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(
            "doc.set('Canvas/Title', { 'kind.content': 'One' });\nthrow new Error('no thanks');\n",
            named: "abort.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--json")

        #expect(run.status == ExitCode.cleanNegative.rawValue)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any]
        )
        let error = try #require(object["error"] as? [String: Any])
        #expect(error["message"] as? String == "no thanks")
        #expect(error["line"] as? Int == 2)
        #expect((error["source"] as? String)?.hasSuffix("abort.js") == true)
        #expect(object["commit"] as? String == "rolledBack")
        #expect(object["documentRevision"] == nil)
        // The write it got as far as is still on the timeline; it was simply not kept.
        let events = try #require(object["events"] as? [[String: Any]])
        #expect(events.count == 1)
    }

    @Test("A dry run's JSON carries dryRun and the findings, and names no revision")
    func dryRunJSONCarriesTheFlag() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(
            "doc.set('Canvas/Cards/First', { 'kind.width': 900 })", named: "wide.js", in: fixture
        )

        let run = try fixture.run("js", fixture.file.path, "-F", path, "--dry-run", "--json")

        #expect(run.status == 0)
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(run.stdout.utf8)) as? [String: Any]
        )
        #expect(object["dryRun"] as? Bool == true)
        #expect(object["commit"] as? String == "previewed")
        #expect(object["documentRevision"] == nil)
        let findings = try #require(object["lint"] as? [[String: Any]])
        #expect(findings.count == 2)
        #expect(findings.allSatisfy { $0["check"] as? String == "clipped" })
    }

    // MARK: - Warnings

    @Test("A script that leaves two artboards overlapping warns on stderr and in the JSON")
    func rootOverlapsAreWarnedAbout() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script(
            "doc.set('Board', { 'common.x': 0, 'common.y': 0 })", named: "stack.js", in: fixture
        )

        let text = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana")
        #expect(text.status == 0)
        #expect(text.stderr.contains("warning artboard-overlap"))

        let second = try CommandFixture(fixture: "batch.pen")
        let secondPath = try script(
            "doc.set('Board', { 'common.x': 0, 'common.y': 0 })", named: "stack.js", in: second
        )
        let json = try second.run("js", second.file.path, "-F", secondPath, "--as", "ana", "--json")
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(json.stdout.utf8)) as? [String: Any]
        )
        let warnings = try #require(object["warnings"] as? [String])
        #expect(warnings.contains { $0.contains("artboard-overlap") })
    }

    @Test("The overlap is on the run's timeline, and prints once on each surface")
    func rootOverlapsComeFromTheTimeline() throws {
        let fixture = try CommandFixture(fixture: "lint/artboard-overlap-clean.pen")
        let body = "doc.set('Chk01', { 'common.x': 100 })"
        let path = try script(body, named: "slide.js", in: fixture)

        let text = try fixture.run("js", fixture.file.path, "-F", path, "--as", "ana")
        #expect(text.status == 0)
        let printed = text.stderr.split(separator: "\n").filter { $0.contains("artboard-overlap") }
        #expect(printed.count == 1)
        #expect(printed.first?.hasPrefix("warning artboard-overlap  Checkout (Chk01)  ") == true)

        let second = try CommandFixture(fixture: "lint/artboard-overlap-clean.pen")
        let secondPath = try script(body, named: "slide.js", in: second)
        let json = try second.run("js", second.file.path, "-F", secondPath, "--as", "ana", "--json")
        let object = try #require(
            JSONSerialization.jsonObject(with: Data(json.stdout.utf8)) as? [String: Any]
        )
        let warnings = try #require(object["warnings"] as? [String])
        #expect(warnings.count == 1)
        let events = try #require(object["events"] as? [[String: Any]])
        let overlaps = events.filter { $0["event"] as? String == "overlap" }
        #expect(overlaps.count == 1)
        #expect(overlaps.first?["text"] as? String == warnings.first)
    }

    @Test("A completion value JSON cannot carry warns rather than printing a result")
    func anUncrossableResultWarns() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let path = try script("(function () { return 1; })", named: "fn.js", in: fixture)

        let run = try fixture.run("js", fixture.file.path, "-F", path)

        #expect(run.status == 0)
        #expect(!run.stdout.contains("result  "))
        #expect(run.stderr.contains("warning  "))
        #expect(run.stderr.contains("function"))
    }
}
