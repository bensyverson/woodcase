//
//  ImportedLibraryCommandTests.swift
//  WoodcaseCommandTests
//

import ArgumentParser
import Foundation
import Testing
@testable import WoodcaseCommandCore

/// Every verb reads the libraries a file's `imports` name, with no flag: the file says
/// where its components live, and `tree`, `lint` and `shot` all see them.
///
/// `imports/app.pen` imports `K` from `kit.lib.pen` beside it and names no font family,
/// so `shot` here measures in the system face and never downloads anything — see
/// `CommandFixtureFontsTests`.
@Suite("imported libraries on the command line")
struct ImportedLibraryCommandTests {
    /// `app.pen` with its library beside it.
    static func fixture(withLibrary: Bool = true) throws -> CommandFixture {
        let fixture = try CommandFixture(fixture: "imports/app.pen")
        if withLibrary { try fixture.copy(fixture: "imports/kit.lib.pen") }
        return fixture
    }

    @Test("tree settles an imported instance to its component's size")
    func treeSettlesImportedInstance() throws {
        let fixture = try Self.fixture()

        let run = try fixture.run("tree", fixture.file.path)

        #expect(run.status == 0, "\(run.stderr)")
        let row = try #require(run.stdoutLines.first { $0.contains("Ins01") })
        #expect(row.contains("80×24"), "\(row)")
    }

    @Test("lint passes a document whose imports resolve")
    func lintPassesResolvedImports() throws {
        let fixture = try Self.fixture()

        let run = try fixture.run("lint", fixture.file.path)

        #expect(run.status == 0, "\(run.stdout)\(run.stderr)")
    }

    @Test("lint reports a missing library once, and still reads the file")
    func lintReportsMissingLibrary() throws {
        let fixture = try Self.fixture(withLibrary: false)

        let run = try fixture.run("lint", fixture.file.path)

        #expect(run.status == 1)
        #expect(run.stdoutLines.count(where: { $0.contains("import-not-found") }) == 1, "\(run.stdout)")
    }

    @Test("shot renders an instance of an imported component")
    func shotRendersImportedInstance() throws {
        let fixture = try Self.fixture()
        let output = fixture.root.appendingPathComponent("plain.png").path

        let run = try fixture.run("shot", fixture.file.path, "screen/plain", "--out", output, "--json")

        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdout.contains("\"width\":80") || run.stdout.contains("\"width\" : 80"), "\(run.stdout)")
    }

    @Test("render draws imported instances: with the library beside it the image differs")
    func renderDrawsImportedInstances() throws {
        func render(withLibrary: Bool) throws -> Data {
            let fixture = try Self.fixture(withLibrary: withLibrary)
            let run = try fixture.run("render", fixture.file.path, "--scale", "1")
            #expect(run.status == 0, "\(run.stderr)")
            let image = try #require(
                FileManager.default.contentsOfDirectory(atPath: fixture.root.path)
                    .first { $0.hasSuffix(".png") && $0.contains("screen") }
            )
            return try Data(contentsOf: fixture.root.appendingPathComponent(image))
        }

        #expect(try render(withLibrary: true) != render(withLibrary: false))
    }

    @Test("render no longer takes --library: the file's own imports are read")
    func renderRefusesLibraryFlag() throws {
        let fixture = try Self.fixture()

        let run = try fixture.run("render", fixture.file.path, "--library", "kit.lib.pen")

        #expect(run.status == ExitCode.usage.rawValue, "\(run.stderr)")
    }
}
