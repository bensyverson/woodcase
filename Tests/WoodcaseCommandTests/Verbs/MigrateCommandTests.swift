//
//  MigrateCommandTests.swift
//  Woodcase
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

@Suite("woodcase migrate")
struct MigrateCommandTests {
    // MARK: - Argument parsing

    @Test("Parses a single input with default flags")
    func minimalArguments() throws {
        let command = try Migrate.parse(["a.pen"])
        #expect(command.inputs.map(\.path) == ["a.pen"])
        #expect(command.dryRun == false)
        #expect(command.force == false)
    }

    @Test("Parses several inputs and both flags")
    func flagsAndSeveralInputs() throws {
        let command = try Migrate.parse([
            "a.pen", "Tests", "--dry-run", "--force", "--exclude", "Tests/Fixtures/v2.9",
        ])
        #expect(command.inputs.map(\.path) == ["a.pen", "Tests"])
        #expect(command.dryRun)
        #expect(command.force)
        #expect(command.exclude == ["Tests/Fixtures/v2.9"])
    }

    // MARK: - Discovery

    @Test("Directories are searched recursively for .pen files, sorted by path")
    func discoversPenFilesRecursively() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let nested = root.appendingPathComponent("nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Self.write(Self.legacyJSON, to: root.appendingPathComponent("b.pen"))
        try Self.write(Self.legacyJSON, to: nested.appendingPathComponent("a.pen"))
        try Self.write("not a pen file", to: root.appendingPathComponent("notes.txt"))

        let found = try Migrate.penFiles(in: [PenInputPath(root.path)]).map(\.path)
        #expect(found == [
            root.appendingPathComponent("b.pen").path,
            nested.appendingPathComponent("a.pen").path,
        ])
    }

    @Test("An excluded directory is left out of the search")
    func excludedDirectoryIsSkipped() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacy = root.appendingPathComponent("v2.9")
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Self.write(Self.legacyJSON, to: root.appendingPathComponent("b.pen"))
        try Self.write(Self.legacyJSON, to: legacy.appendingPathComponent("a.pen"))

        let found = try Migrate.penFiles(in: [PenInputPath(root.path)], excluding: [legacy.path])
        #expect(found.map(\.lastPathComponent) == ["b.pen"])
    }

    @Test("An excluded file is left out of the search")
    func excludedFileIsSkipped() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let keep = root.appendingPathComponent("keep.pen")
        let drop = root.appendingPathComponent("drop.pen")
        try Self.write(Self.legacyJSON, to: keep)
        try Self.write(Self.legacyJSON, to: drop)

        let found = try Migrate.penFiles(in: [PenInputPath(root.path)], excluding: [drop.path])
        #expect(found.map(\.lastPathComponent) == ["keep.pen"])
    }

    @Test("A file argument that is not a .pen file is a usage error")
    func rejectsNonPenFile() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("notes.txt")
        try Self.write("hello", to: path)

        let thrown = #expect(throws: CommandFailure.self) {
            _ = try Migrate.penFiles(in: [PenInputPath(path.path)])
        }
        #expect(try #require(thrown).exitCode == .usage)
    }

    @Test("A path that names nothing is a target failure, not a usage error")
    func rejectsMissingPath() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let thrown = #expect(throws: CommandFailure.self) {
            _ = try Migrate.penFiles(in: [PenInputPath(root.appendingPathComponent("gone.pen").path)])
        }
        #expect(try #require(thrown).exitCode == .targetFailure)
    }

    // MARK: - Writing

    @Test("A legacy file is rewritten in the current format")
    func rewritesLegacyFile() async throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("legacy.pen")
        try Self.write(Self.legacyJSON, to: file)

        var command = try Migrate.parse([file.path])
        try await command.run()

        let rewritten = try String(contentsOf: file, encoding: .utf8)
        #expect(rewritten.contains("\"version\": \"2.19\""))
        #expect(!rewritten.contains("thickness"))
    }

    @Test("--dry-run leaves the file untouched")
    func dryRunDoesNotWrite() async throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("legacy.pen")
        try Self.write(Self.legacyJSON, to: file)

        var command = try Migrate.parse([file.path, "--dry-run"])
        try await command.run()

        #expect(try String(contentsOf: file, encoding: .utf8) == Self.legacyJSON)
    }

    @Test("A file already at the current version is left untouched")
    func currentFileIsSkipped() async throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("current.pen")
        try Self.write(Self.currentJSON, to: file)

        var command = try Migrate.parse([file.path])
        try await command.run()

        #expect(try String(contentsOf: file, encoding: .utf8) == Self.currentJSON)
    }

    @Test("--force rewrites a file already at the current version")
    func forceRewritesCurrentFile() async throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("current.pen")
        try Self.write(Self.currentJSON, to: file)

        var command = try Migrate.parse([file.path, "--force"])
        try await command.run()

        let rewritten = try String(contentsOf: file, encoding: .utf8)
        #expect(rewritten != Self.currentJSON)
        #expect(rewritten.contains("\"version\": \"2.19\""))
    }

    @Test("A file that cannot be parsed is a target failure, and the others still run")
    func unparsableFileFailsTheRun() async throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        try Self.write("not json", to: root.appendingPathComponent("broken.pen"))
        let good = root.appendingPathComponent("legacy.pen")
        try Self.write(Self.legacyJSON, to: good)

        var command = try Migrate.parse([root.path])
        await #expect(throws: ExitCode.targetFailure) {
            try await command.run()
        }
        #expect(try String(contentsOf: good, encoding: .utf8).contains("\"version\": \"2.19\""))
    }

    // MARK: - Helpers

    private static let legacyJSON = """
    {
      "version": "2.9",
      "children": [
        {
          "type": "rectangle",
          "id": "r1",
          "width": 100,
          "height": 50,
          "stroke": { "fill": "#FF0000", "thickness": 2 }
        }
      ]
    }
    """

    private static let currentJSON = """
    {"children":[{"height":50,"id":"r1","type":"rectangle","width":100}],"version":"2.19"}
    """

    private static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("woodcase-migrate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private static func write(_ contents: String, to url: URL) throws {
        try Data(contents.utf8).write(to: url)
    }
}
