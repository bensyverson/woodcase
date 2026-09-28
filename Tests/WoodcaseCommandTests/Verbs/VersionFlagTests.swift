//
//  VersionFlagTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase --version`.
///
/// The first thing anything automated asks a tool it has not met, and the only way an
/// agent can tell a verb it cannot find from a build too old to have it. It exits 0 and
/// puts the answer on standard output, like every other read.
@Suite("woodcase --version")
struct VersionFlagTests {
    @Test("--version prints the package version and exits 0")
    func printsTheVersion() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("--version")

        #expect(run.status == 0)
        #expect(run.stdoutLines == [WoodcaseVersion.line])
        #expect(run.stdout.hasPrefix(WoodcaseVersion.current))
    }

    @Test("The line names the .pen format the tool writes, from the writer's own constant")
    func namesThePenFormatItWrites() {
        #expect(WoodcaseVersion.line == "\(WoodcaseVersion.current) (.pen \(PenFormatVersion.current))")
    }

    @Test("The first whitespace-separated field is the version alone")
    func firstFieldIsTheBareVersion() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("--version")

        #expect(run.stdout.split(separator: " ").first.map(String.init) == WoodcaseVersion.current)
    }
}
