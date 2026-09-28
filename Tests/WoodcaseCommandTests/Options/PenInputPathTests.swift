//
//  PenInputPathTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

/// The file-or-directory argument. Like ``PenFilePath``, it parses anything and asks
/// about the world only when the verb runs: a missing path is a target failure (4),
/// while naming a file of the wrong kind is a usage error (2).
@Suite("The .pen file-or-directory argument")
struct PenInputPathTests {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenInputPathTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test("Any string parses; existence is not a parse-time question")
    func acceptsAnyArgument() throws {
        let path = try #require(PenInputPath(argument: "nowhere/at/all.pen"))
        #expect(path.url.lastPathComponent == "all.pen")
    }

    @Test("A leading tilde is expanded")
    func expandsTilde() throws {
        let path = try #require(PenInputPath(argument: "~/designs"))
        #expect(!path.path.hasPrefix("~"))
        #expect(path.path.hasSuffix("/designs"))
    }

    @Test("An existing .pen file resolves to a file target")
    func existingPenFileResolves() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("a.pen")
        try Data("{}".utf8).write(to: file)

        let target = try PenInputPath(file.path).existingTarget()
        #expect(target == .file(file.standardizedFileURL))
    }

    @Test("An existing directory resolves to a directory target")
    func existingDirectoryResolves() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let target = try PenInputPath(directory.path).existingTarget()
        #expect(target == .directory(URL(fileURLWithPath: directory.path).standardizedFileURL))
    }

    @Test("A missing path is exit 4, with the same sentence PenFilePath uses")
    func missingPathIsTargetFailure() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let missing = directory.appendingPathComponent("gone.pen")

        let thrown = #expect(throws: CommandFailure.self) {
            try PenInputPath(missing.path).existingTarget()
        }
        let caught = try #require(thrown)
        #expect(caught.exitCode == .targetFailure)
        #expect(caught.message.contains("Cannot open \(missing.path): no such file."))
        #expect(caught.message.contains("`ls \(directory.path)`"))
    }

    @Test("A file that is not a .pen file is exit 2, and the message names what it wanted")
    func nonPenFileIsUsageError() throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let notes = directory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: notes)

        let thrown = #expect(throws: CommandFailure.self) {
            try PenInputPath(notes.path).existingTarget()
        }
        let caught = try #require(thrown)
        #expect(caught.exitCode == .usage)
        #expect(caught.message.contains(notes.path))
        #expect(caught.message.contains(".pen file"))
    }
}
