//
//  MigrateMetadataNamespaceTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase migrate` moves every old-style Woodcase metadata key — bare post-it keys,
/// underscore code-gen keys — under `metadata.woodcase`, in a file already at the
/// current format version, as one logged edit; and `lint --severity notice` names the
/// old spellings beforehand.
@Suite("woodcase migrate: the metadata namespace")
struct MigrateMetadataNamespaceTests {
    /// The file's metadata objects, by node id.
    private func metadata(in fixture: CommandFixture) throws -> [String: [String: Any]] {
        let root = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: fixture.file)) as? [String: Any])
        var found: [String: [String: Any]] = [:]
        func walk(_ nodes: [[String: Any]]) {
            for node in nodes {
                if let id = node["id"] as? String, let metadata = node["metadata"] as? [String: Any] {
                    found[id] = metadata
                }
                walk(node["children"] as? [[String: Any]] ?? [])
            }
        }
        walk(root["children"] as? [[String: Any]] ?? [])
        return found
    }

    @Test("lint names the old spellings as a notice")
    func lintNamesOldSpellings() throws {
        let fixture = try CommandFixture(fixture: "metadata-old-style.pen")

        let run = try fixture.run("lint", fixture.file.path, "--severity", "notice")

        #expect(run.stdout.contains("metadata-old-style"), "lint printed \(run.stdout)")
        #expect(run.stdout.contains("_role"))
    }

    @Test("migrate moves every old spelling under metadata.woodcase, keeping a legacy kind")
    func migrateConvertsTheFile() throws {
        let fixture = try CommandFixture(fixture: "metadata-old-style.pen")

        let run = try fixture.run("migrate", fixture.file.path, "--as", "bob")

        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout.contains("metadata"), "migrate printed \(run.stdout)")
        let written = try metadata(in: fixture)
        let note = try #require(written["Nte01"])
        #expect(note["type"] as? String == "woodcase")
        #expect(note["kind"] as? String == "question")
        let noteNamespace = try #require(note["woodcase"] as? [String: Any])
        #expect(noteNamespace["type"] as? String == "postit")
        #expect(noteNamespace["state"] as? String == "open")
        #expect(noteNamespace["tint"] as? String == "#A5D6A7")
        let button = try #require(written["Btn01"])
        #expect(button["_role"] == nil)
        #expect(button["_props"] == nil)
        #expect((button["woodcase"] as? [String: Any])?["role"] as? String == "button")

        let lint = try fixture.run("lint", fixture.file.path, "--severity", "notice")
        #expect(!lint.stdout.contains("metadata-old-style"), "lint still reports \(lint.stdout)")
    }

    @Test("migrate --dry-run leaves the file untouched")
    func dryRunLeavesTheFile() throws {
        let fixture = try CommandFixture(fixture: "metadata-old-style.pen")
        let before = try Data(contentsOf: fixture.file)

        let run = try fixture.run("migrate", fixture.file.path, "--dry-run")

        #expect(run.status == 0, "\(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
        #expect(run.stdout.contains("(old-style metadata on 2 node(s)") && run.stdout.contains("would migrate"), "migrate printed \(run.stdout)")
    }

    @Test("A second migrate finds nothing left to move")
    func migrateIsIdempotent() throws {
        let fixture = try CommandFixture(fixture: "metadata-old-style.pen")
        let original = try Data(contentsOf: fixture.file)
        _ = try fixture.run("migrate", fixture.file.path)
        let once = try Data(contentsOf: fixture.file)
        #expect(once != original)

        let run = try fixture.run("migrate", fixture.file.path)

        #expect(run.status == 0, "\(run.stderr)")
        #expect(try Data(contentsOf: fixture.file) == once)
        #expect(run.stdout.contains("skipped 1"), "migrate printed \(run.stdout)")
    }
}
