//
//  UnreadableFileTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

/// A .pen file that is there but will not decode.
///
/// The subject is the sentence an agent reads: it must name the file, say what the
/// decoder actually objected to, and name a next command — and it must be the *same*
/// sentence whichever verb was run, whether that verb parses the file itself
/// (`render`) or opens it under a transaction (`tree`, `lint`).
@Suite("An unreadable .pen file")
struct UnreadableFileTests {
    /// The verbs a broken file is most likely to be met by, each taking a path.
    private static let verbs = ["tree", "render", "lint"]

    // MARK: - Bytes that are not JSON at all

    @Test("Every verb names the file, the reason and a next command", arguments: verbs)
    func garbageIsNamedWithARemedy(verb: String) throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let broken = try Self.write("this is not json", to: "broken.pen", in: fixture)
        let run = try fixture.run(verb, broken.path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("Cannot read \(broken.path): not a .pen document"))
        #expect(run.stderr.contains("not valid JSON"))
        #expect(run.stderr.contains("`python3 -m json.tool \(broken.path)`"))
    }

    @Test("The old bare Foundation sentence is gone")
    func foundationNoiseIsGone() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let broken = try Self.write("this is not json", to: "broken.pen", in: fixture)
        let run = try fixture.run("tree", broken.path)

        #expect(!run.stderr.contains("The data couldn’t be read because it isn’t in the correct format."))
    }

    // MARK: - JSON whose shape is wrong

    @Test("A key of the wrong type is named by its path and its type", arguments: verbs)
    func badKeyTypeIsNamed(verb: String) throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let broken = try Self.write(
            #"{"version": "2.17", "children": [{"id": 5, "type": "rectangle"}]}"#,
            to: "badkey.pen",
            in: fixture
        )
        let run = try fixture.run(verb, broken.path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("Cannot read \(broken.path): not a .pen document"))
        #expect(run.stderr.contains("children[0].id should be a string"))
        #expect(run.stderr.contains("`python3 -m json.tool \(broken.path)`"))
    }

    // MARK: - A version this build cannot read

    @Test("An unreadable format version says so, and what this build reads", arguments: verbs)
    func unsupportedVersionIsNamed(verb: String) throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let broken = try Self.write(
            #"{"version": "3.0", "children": []}"#,
            to: "future.pen",
            in: fixture
        )
        let run = try fixture.run(verb, broken.path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("Cannot read \(broken.path):"))
        #expect(run.stderr.contains("\"3.0\""))
        #expect(run.stderr.contains("update Woodcase"))
        #expect(run.stderr.contains("`python3 -m json.tool \(broken.path)`"))
    }

    // MARK: - One sentence, every verb

    @Test("Every verb prints the same sentence for the same broken file")
    func oneSentenceForEveryVerb() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let broken = try Self.write(
            #"{"version": "2.17", "children": [{"id": 5, "type": "rectangle"}]}"#,
            to: "badkey.pen",
            in: fixture
        )

        let messages = try Self.verbs.map { verb in
            try fixture.run(verb, broken.path).stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #expect(Set(messages).count == 1, "verbs disagreed: \(messages)")
    }

    // MARK: - Helpers

    /// Writes a broken document beside the fixture and returns its URL.
    private static func write(_ contents: String, to name: String, in fixture: CommandFixture) throws -> URL {
        let url = fixture.root.appendingPathComponent(name)
        try Data(contents.utf8).write(to: url)
        return url
    }
}
