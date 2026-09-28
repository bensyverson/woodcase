//
//  VendorWordsTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// Pins the ruling that Woodcase names the `.pen` format only, never the editor that
/// happens to produce it, its MCP, or its documentation.
///
/// Every verb, the bare primer, and the `help design` / `help schema` topics are driven
/// through the real binary — what an agent actually reads — and checked for the words a
/// caller must never see. The DocC sources get the same check directly, since they never
/// reach a caller through the binary at all.
@Suite("No vendor words in caller-facing text")
struct VendorWordsTests {
    /// Every subcommand `woodcase --help` lists, in the order the primer prints them.
    static let verbs = [
        "tree", "get", "shot", "lint", "schema", "undo",
        "new", "add", "set", "replace", "cp", "mv", "rm", "override", "apply",
        "vars", "imports", "render", "themes", "generate", "migrate",
        "activity", "icons", "serve", "help",
    ]

    /// A word naming the vendor, its app, its domain, or its assistant integration —
    /// none of which a `.pen` caller needs to know. Checked case-insensitively.
    static let vendorWords = ["pen.app", "pencil", "pen.dev", "mcp"]

    @Test("The bare primer names no vendor word")
    func primerIsClean() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run([])
        assertNoVendorWords(in: run.stdout, context: "the bare primer")
    }

    @Test("`help design` and `help schema` name no vendor word")
    func helpTopicsAreClean() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        for topic in ["design", "schema"] {
            let run = try fixture.run("help", topic)
            assertNoVendorWords(in: run.stdout, context: "`woodcase help \(topic)`")
        }
    }

    @Test("Every verb's --help names no vendor word", arguments: verbs)
    func verbHelpIsClean(verb: String) throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(verb, "--help")
        assertNoVendorWords(in: run.stdout, context: "`woodcase \(verb) --help`")
    }

    @Test("The DocC sources name no vendor word")
    func docCIsClean() throws {
        for url in Self.docCFiles {
            let text = try String(contentsOf: url, encoding: .utf8)
            assertNoVendorWords(in: text, context: url.lastPathComponent)
        }
    }

    /// Fails the test for every vendor word found in `text`, naming the word and where
    /// it was checked so a failure points straight at the sentence to fix.
    private func assertNoVendorWords(in text: String, context: String, sourceLocation: SourceLocation = #_sourceLocation) {
        let lowered = text.lowercased()
        for word in Self.vendorWords {
            #expect(!lowered.contains(word), "\(context) names the vendor word \"\(word)\"", sourceLocation: sourceLocation)
        }
    }

    /// The package's DocC markdown files, found relative to this file rather than the
    /// working directory, so the test does not depend on where `swift test` was invoked.
    private static let docCFiles: [URL] = {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let docCDirectory = packageRoot
            .appendingPathComponent("Sources/Woodcase/Documentation.docc", isDirectory: true)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: docCDirectory.path)) ?? []
        return names
            .filter { $0.hasSuffix(".md") }
            .map { docCDirectory.appendingPathComponent($0) }
    }()
}
