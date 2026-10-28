//
//  FileTokenPreservationTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// Every `woodcase` verb that writes a .pen file leaves the document's top-level
/// `fileToken` exactly as it found it, and invents none for a file that had none.
///
/// Pen.app finds a document's comments by `fileToken` (see
/// `project/2026-10-23-pen-cli-0.3.13.md`, *Comments*): a copy whose only change was a
/// fresh token opened with none of them. A tool that drops or regenerates it orphans a
/// Pen user's comments, so the guarantee is pinned per verb, through the built binary,
/// rather than assumed from the one shared write path.
///
/// The table is checked against the command registry: a new leaf verb whose abstract
/// starts `Write:` fails ``everyWriteVerbIsInTheTable()`` until it has a row here.
@Suite("fileToken survives every write verb")
struct FileTokenPreservationTests {
    // MARK: - The table

    /// One write verb, driven the way an agent would, against a copy of a fixture.
    struct Case: CustomStringConvertible {
        /// The verb's name as the registry spells it — `vars set`, not `VarsSetCommand`.
        let verb: String

        /// A label for the variant, when one verb has several rows.
        var variant: String = ""

        /// The fixture the case starts from, which gets ``FileTokenPreservationTests/token``.
        let fixture: String

        /// Whether the written file is the same document, and so keeps its token.
        /// `false` only for a verb that creates a new file, which starts without one.
        var carriesToken: Bool = true

        /// Runs the verb (and whatever set-up it needs), asserting each run succeeded.
        ///
        /// - Returns: The .pen file the verb wrote, for the token to be read back from.
        let run: @Sendable (CommandFixture) throws -> URL

        var description: String {
            variant.isEmpty ? verb : "\(verb) (\(variant))"
        }
    }

    /// A token with characters a careless encoder would change: a slash, a plus, a
    /// non-ASCII letter and a trailing run of `=`.
    static let token = "Tok/en+é-0001=="

    /// Runs one command and requires it to succeed.
    private static func succeed(_ fixture: CommandFixture, _ arguments: String...) throws -> CommandRun {
        let run = try fixture.run(arguments)
        #expect(run.status == 0, "woodcase \(arguments.joined(separator: " ")): \(run.stderr)")
        return run
    }

    /// Writes a body file beside the fixture and returns its path.
    private static func body(_ text: String, named name: String, in fixture: CommandFixture) throws -> String {
        let url = fixture.root.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url.path
    }

    /// A bundle made from the fixture's own file, so the token it carries is under test.
    private static func bundled(_ fixture: CommandFixture) throws -> URL {
        _ = try succeed(fixture, "bundle", fixture.file.path, "--as", "ana")
        return fixture.root.appendingPathComponent("batch.umbra")
    }

    /// Every write verb the registry lists, one row each (two for `migrate`, which has two
    /// ways to rewrite a file).
    static let cases: [Case] = [
        Case(verb: "new", fixture: "batch.pen", carriesToken: false) { fixture in
            let fresh = fixture.root.appendingPathComponent("fresh.pen")
            _ = try succeed(fixture, "new", fresh.path, "--as", "ana")
            return fresh
        },
        Case(verb: "add", fixture: "batch.pen") { fixture in
            let file = try body(#"{"type":"frame","name":"Hero","width":10,"height":10}"#, named: "add.json", in: fixture)
            _ = try succeed(fixture, "add", fixture.file.path, "Canvas", "-F", file, "--as", "ana")
            return fixture.file
        },
        Case(verb: "set", fixture: "batch.pen") { fixture in
            _ = try succeed(fixture, "set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--as", "ana")
            return fixture.file
        },
        Case(verb: "replace", fixture: "batch.pen") { fixture in
            let file = try body(#"{"type":"frame","name":"Cards","children":[]}"#, named: "replace.json", in: fixture)
            _ = try succeed(fixture, "replace", fixture.file.path, "Canvas/Cards", "-F", file, "--as", "ana")
            return fixture.file
        },
        Case(verb: "cp", fixture: "batch.pen") { fixture in
            _ = try succeed(fixture, "cp", fixture.file.path, "Canvas/Cards/First", "Board", "--as", "ana")
            return fixture.file
        },
        Case(verb: "paste", fixture: "batch.pen") { fixture in
            let source = try fixture.copy(fixture: "clip.pen")
            let clip = try succeed(fixture, "clip", source.path, "BtnI", "--json")
            let file = try body(clip.stdout, named: "clip.json", in: fixture)
            _ = try succeed(fixture, "paste", fixture.file.path, file, "--as", "ana")
            return fixture.file
        },
        Case(verb: "mv", fixture: "batch.pen") { fixture in
            _ = try succeed(fixture, "mv", fixture.file.path, "Canvas/Cards/First", "Board", "--as", "ana")
            return fixture.file
        },
        Case(verb: "group", fixture: "batch.pen") { fixture in
            _ = try succeed(
                fixture, "group", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards/Second", "--as", "ana"
            )
            return fixture.file
        },
        Case(verb: "ungroup", fixture: "batch.pen") { fixture in
            let grouped = try succeed(
                fixture, "group", fixture.file.path, "Canvas/Cards/First", "Canvas/Cards/Second", "--as", "ana", "--json"
            )
            let report = try JSONDecoder().decode(GroupCommand.Report.self, from: Data(grouped.stdout.utf8))
            _ = try succeed(fixture, "ungroup", fixture.file.path, "#\(report.id)", "--as", "ana")
            return fixture.file
        },
        Case(verb: "scale", fixture: "batch.pen") { fixture in
            _ = try succeed(fixture, "scale", fixture.file.path, "Canvas", "--by", "2", "--as", "ana")
            return fixture.file
        },
        Case(verb: "rm", fixture: "batch.pen") { fixture in
            _ = try succeed(fixture, "rm", fixture.file.path, "Canvas/Cards/First", "--as", "ana")
            return fixture.file
        },
        Case(verb: "override", fixture: "addressing.pen") { fixture in
            _ = try succeed(fixture, "override", fixture.file.path, "Dashboard/Body/Nav/Label", "content=Changed", "--as", "ana")
            return fixture.file
        },
        Case(verb: "apply", fixture: "batch.pen") { fixture in
            let ops = try body(
                #"{"op":"set","target":"Canvas/Title","props":{"kind.content":"Applied"}}"# + "\n",
                named: "ops.jsonl", in: fixture
            )
            _ = try succeed(fixture, "apply", fixture.file.path, "-F", ops, "--as", "ana")
            return fixture.file
        },
        Case(verb: "js", fixture: "batch.pen") { fixture in
            let script = try body("doc.cp('Canvas/Cards', 'Board')", named: "copy.js", in: fixture)
            _ = try succeed(fixture, "js", fixture.file.path, "-F", script, "--as", "ana")
            return fixture.file
        },
        Case(verb: "undo", fixture: "batch.pen") { fixture in
            _ = try succeed(fixture, "set", fixture.file.path, "Canvas/Title", "kind.content=Hello", "--as", "ana")
            _ = try succeed(fixture, "undo", fixture.file.path, "--as", "ana")
            return fixture.file
        },
        Case(verb: "comment", fixture: "notes-comments-prompts.pen") { fixture in
            _ = try succeed(fixture, "comment", fixture.file.path, "--at", "900,40", "Legend?", "--as", "ana")
            return fixture.file
        },
        Case(verb: "reply", fixture: "notes-comments-prompts.pen") { fixture in
            _ = try succeed(fixture, "reply", fixture.file.path, "Cm02", "On it.", "--as", "claude")
            return fixture.file
        },
        Case(verb: "resolve", fixture: "notes-comments-prompts.pen") { fixture in
            _ = try succeed(fixture, "resolve", fixture.file.path, "Cm03", "--as", "ana")
            return fixture.file
        },
        Case(verb: "vars set", fixture: "parser-variables.pen") { fixture in
            _ = try succeed(fixture, "vars", "set", fixture.file.path, "brand=#FF6600", "--as", "ana")
            return fixture.file
        },
        Case(verb: "vars rm", fixture: "parser-variables.pen") { fixture in
            _ = try succeed(fixture, "vars", "rm", fixture.file.path, "showSubtitle", "--as", "ana")
            return fixture.file
        },
        Case(verb: "vars axis add", fixture: "parser-variables.pen") { fixture in
            _ = try succeed(fixture, "vars", "axis", "add", fixture.file.path, "mode=light,dark", "--as", "ana")
            return fixture.file
        },
        Case(verb: "imports set", fixture: "batch.pen") { fixture in
            _ = try succeed(fixture, "imports", "set", fixture.file.path, "lib", "./library.pen", "--as", "ana")
            return fixture.file
        },
        Case(verb: "imports rm", fixture: "imports.pen") { fixture in
            _ = try succeed(fixture, "imports", "rm", fixture.file.path, "icons", "--as", "ana")
            return fixture.file
        },
        Case(verb: "bundle", fixture: "batch.pen") { fixture in
            try bundled(fixture).appendingPathComponent("document.pen")
        },
        Case(verb: "unbundle", fixture: "batch.pen") { fixture in
            let bundle = try bundled(fixture)
            let out = fixture.root.appendingPathComponent("out")
            _ = try succeed(fixture, "unbundle", bundle.path, "--to", out.path, "--as", "ana")
            return out.appendingPathComponent("batch.pen")
        },
        Case(verb: "embed", fixture: "batch.pen") { fixture in
            let bundle = try bundled(fixture)
            _ = try succeed(fixture, "embed", bundle.path)
            return bundle.appendingPathComponent("document.pen")
        },
        Case(verb: "migrate", variant: "older version", fixture: "batch.pen") { fixture in
            try legacy(fixture)
            _ = try succeed(fixture, "migrate", fixture.file.path, "--as", "ana")
            let version = try object(fixture.file)["version"] as? String
            #expect(version != "2.9", "the 2.9 file was not rewritten, so this row proved nothing")
            return fixture.file
        },
        Case(verb: "migrate", variant: "--force", fixture: "batch.pen") { fixture in
            _ = try succeed(fixture, "migrate", fixture.file.path, "--force", "--as", "ana")
            return fixture.file
        },
    ]

    /// Declares the fixture's file as a 2.9 document, which only `migrate` rewrites; its
    /// token, if it has one, is left alone.
    private static func legacy(_ fixture: CommandFixture) throws {
        var document = try object(fixture.file)
        document["version"] = "2.9"
        try JSONSerialization.data(withJSONObject: document).write(to: fixture.file)
    }

    // MARK: - Helpers

    /// Puts ``token`` in the file's top-level object, or takes any out.
    private static func setToken(_ token: String?, in url: URL) throws {
        var document = try object(url)
        document["fileToken"] = token
        try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys]).write(to: url)
    }

    /// A .pen file's top-level JSON object.
    private static func object(_ url: URL) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }

    /// The leaf commands under `type` with the abstract each one prints in `--help`.
    private static func leaves(of type: any ParsableCommand.Type, path: [String]) -> [(name: String, abstract: String)] {
        let subcommands = type.configuration.subcommands
        guard !subcommands.isEmpty else {
            return [(path.joined(separator: " "), type.configuration.abstract)]
        }
        return subcommands.flatMap { leaves(of: $0, path: path + [$0._commandName]) }
    }

    // MARK: - The guarantee

    @Test("The token comes back byte for byte after the verb writes", arguments: cases)
    func tokenSurvives(verb: Case) throws {
        let fixture = try CommandFixture(fixture: verb.fixture)
        try Self.setToken(Self.token, in: fixture.file)

        let written = try verb.run(fixture)

        let token = try Self.object(written)["fileToken"] as? String
        #expect(token == (verb.carriesToken ? Self.token : nil))
    }

    @Test("A file with no token still has none after the verb writes", arguments: cases)
    func noTokenIsInvented(verb: Case) throws {
        let fixture = try CommandFixture(fixture: verb.fixture)
        try Self.setToken(nil, in: fixture.file)
        #expect(try Self.object(fixture.file)["fileToken"] == nil)

        let written = try verb.run(fixture)

        #expect(try Self.object(written)["fileToken"] == nil)
    }

    // MARK: - The table covers the registry

    @Test("Every write verb the registry lists has a row in the table")
    func everyWriteVerbIsInTheTable() {
        let registered = Set(
            WoodcaseCommand.configuration.subcommands
                .flatMap { Self.leaves(of: $0, path: [$0._commandName]) }
                .filter { $0.abstract.hasPrefix("Write:") }
                .map(\.name)
        )
        let covered = Set(Self.cases.map(\.verb))

        #expect(
            registered.subtracting(covered).isEmpty,
            "Write verbs with no fileToken row in FileTokenPreservationTests.cases: \(registered.subtracting(covered).sorted())"
        )
        #expect(
            covered.subtracting(registered).isEmpty,
            "Rows for verbs the registry no longer lists as Write: \(covered.subtracting(registered).sorted())"
        )
    }
}
