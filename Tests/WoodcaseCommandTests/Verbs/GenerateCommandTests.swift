//
//  GenerateCommandTests.swift
//  Woodcase
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

@Suite("Generate.React")
struct GenerateCommandTests {
    // MARK: - The input file

    @Test("A file that is not there is exit 4 with the command that would show what is")
    func missingFileIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run(
            "generate", "react", fixture.root.appendingPathComponent("gone.pen").path
        )

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains(fixture.root.appendingPathComponent("gone.pen").path))
        #expect(run.stderr.contains("no such file"))
        #expect(run.stderr.contains("ls "))
    }

    @Test("A directory named where a file belongs is exit 4, and the message says so")
    func directoryIsTargetFailure() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("generate", "react", fixture.root.path)

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(run.stderr.contains("it is a directory"))
    }

    @Test("--force does not clear the output directory when the input is not there")
    func missingFileLeavesTheOutputDirectoryAlone() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let output = fixture.root.appendingPathComponent("ui", isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let keeper = output.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: keeper)

        let run = try fixture.run(
            "generate", "react", fixture.root.appendingPathComponent("gone.pen").path,
            "--output", output.path, "--force"
        )

        #expect(run.status == ExitCode.targetFailure.rawValue)
        #expect(FileManager.default.fileExists(atPath: keeper.path))
    }

    // MARK: - Arguments

    @Test("Parses minimal arguments")
    func minimalArguments() throws {
        let command = try Generate.React.parse(["input.pen"])
        #expect(command.input.path == "input.pen")
        #expect(command.output == ".")
        #expect(command.packaged == false)
        #expect(command.name == nil)
        #expect(command.force == false)
    }

    @Test("--library is not an option: the file's own imports name its libraries")
    func libraryFlagIsRetired() throws {
        #expect(throws: (any Error).self) {
            try Generate.React.parse(["input.pen", "--library", "kit.lib.pen"])
        }
    }

    @Test("Parses --package flag")
    func packageFlag() throws {
        let command = try Generate.React.parse(["input.pen", "--package"])
        #expect(command.packaged == true)
    }

    @Test("Parses --package with --name")
    func packageWithName() throws {
        let command = try Generate.React.parse([
            "input.pen", "--package", "--name", "@myorg/ui",
        ])
        #expect(command.packaged == true)
        #expect(command.name == "@myorg/ui")
    }

    @Test("Parses --force flag")
    func forceFlag() throws {
        let command = try Generate.React.parse(["input.pen", "--force"])
        #expect(command.force == true)
    }

    @Test("--name without --package fails validation")
    func nameWithoutPackageFails() throws {
        // ArgumentParser wraps ValidationError in CommandError during parse,
        // so we validate at the parse level where the error surfaces correctly.
        #expect {
            var command = try Generate.React.parse(["input.pen", "--name", "@myorg/ui"])
            try command.validate()
        } throws: { error in
            String(describing: error).contains("--name requires --package")
        }
    }

    @Test("--name with --package passes validation")
    func nameWithPackagePasses() throws {
        let command = try Generate.React.parse([
            "input.pen", "--package", "--name", "@myorg/ui",
        ])
        #expect(throws: Never.self) {
            try command.validate()
        }
    }

    @Test("Parses --preview flag")
    func previewFlag() throws {
        let command = try Generate.React.parse([
            "input.pen", "--package", "--preview",
        ])
        #expect(command.preview == true)
    }

    @Test("--preview defaults to false")
    func previewDefault() throws {
        let command = try Generate.React.parse(["input.pen"])
        #expect(command.preview == false)
    }

    @Test("--preview without --package fails validation")
    func previewWithoutPackageFails() throws {
        #expect {
            var command = try Generate.React.parse(["input.pen", "--preview"])
            try command.validate()
        } throws: { error in
            String(describing: error).contains("--preview requires --package")
        }
    }

    @Test("--preview with --package passes validation")
    func previewWithPackagePasses() throws {
        let command = try Generate.React.parse([
            "input.pen", "--package", "--preview",
        ])
        #expect(throws: Never.self) {
            try command.validate()
        }
    }
}
