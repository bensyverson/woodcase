//
//  PenFilePathTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

/// The `.pen` file argument. Whether the file *exists* is checked when the verb runs,
/// not when the arguments parse: a missing file is a target failure (4), never a usage
/// error (2), because the invocation's shape was fine.
@Suite("The .pen file argument")
struct PenFilePathTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenFilePathTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Any string parses; existence is not a parse-time question")
    func acceptsAnyArgument() throws {
        let path = try #require(PenFilePath(argument: "nowhere/at/all.pen"))
        #expect(path.url.lastPathComponent == "all.pen")
    }

    @Test("A leading tilde is expanded")
    func expandsTilde() throws {
        let path = try #require(PenFilePath(argument: "~/design.pen"))
        #expect(!path.path.hasPrefix("~"))
        #expect(path.path.hasSuffix("/design.pen"))
    }

    @Test("An existing file resolves to its URL")
    func existingFileResolves() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.pen")
        try Data("{}".utf8).write(to: file)

        let resolved = try PenFilePath(file.path).existingFile()
        #expect(resolved.standardizedFileURL == file.standardizedFileURL)
    }

    @Test("A missing file is exit 4, and the message names the path")
    func missingFileIsTargetFailure() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("gone.pen")

        let thrown = #expect(throws: CommandFailure.self) {
            try PenFilePath(missing.path).existingFile()
        }
        let caught = try #require(thrown)
        #expect(caught.exitCode == .targetFailure)
        #expect(caught.message.contains(missing.path))
        #expect(caught.message.lowercased().contains("no such file"))
    }

    @Test("A missing file's message names `woodcase new` as the next command")
    func missingFileNamesNew() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("gone.pen")

        let thrown = #expect(throws: CommandFailure.self) {
            try PenFilePath(missing.path).existingFile()
        }
        let caught = try #require(thrown)
        #expect(caught.message.contains("woodcase new \(missing.path)"))
    }

    @Test("A directory is exit 4, and the message says so")
    func directoryIsTargetFailure() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let thrown = #expect(throws: CommandFailure.self) {
            try PenFilePath(directory.path).existingFile()
        }
        let caught = try #require(thrown)
        #expect(caught.exitCode == .targetFailure)
        #expect(caught.message.contains("directory"))
    }
}
