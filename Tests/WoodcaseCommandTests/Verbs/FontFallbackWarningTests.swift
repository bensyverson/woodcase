//
//  FontFallbackWarningTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// A measurement taken in a face the render will not use has to say so.
///
/// Fonts used to be prepared only by `shot` and `render`, so `tree` and `lint`
/// reported widths measured in SF Pro and said nothing about it — a plausible wrong
/// answer, which is worse than an error. Every verb that settles a document now runs
/// the offline half of the resolver first and, for a family it cannot place, prints one
/// line naming the font and the face it fell back to.
///
/// Standard output is untouched: the table keeps its shape, the exit code stays 0. An
/// unresolvable family is a fact about the machine, not about the file, and `lint` in
/// particular still declines to judge font names — it has no way to tell a typo from a
/// Google font nobody has downloaded yet.
@Suite("Font fallback warnings")
struct FontFallbackWarningTests {
    /// The family `font-missing.pen` names, which no registry will ever answer to.
    static let missingFamily = "Woodcase No Such Face"

    @Test("tree warns on stderr and leaves its table alone")
    func treeWarns() throws {
        let fixture = try CommandFixture(fixture: "font-missing.pen")
        let run = try fixture.run("tree", fixture.file.path)

        #expect(run.status == 0)
        #expect(run.stderr.contains(Self.missingFamily))
        #expect(run.stderr.contains(PenTextMeasurer.defaultFontFamily))
        #expect(run.stdoutLines.count == 3)
        #expect(!run.stdout.contains(Self.missingFamily))
    }

    @Test("lint warns too, and still reports no finding about the font")
    func lintWarns() throws {
        let fixture = try CommandFixture(fixture: "font-missing.pen")
        let run = try fixture.run("lint", fixture.file.path)

        #expect(run.stderr.contains(Self.missingFamily))
        #expect(!run.stdout.contains(Self.missingFamily))
    }

    @Test("A write verb that prints a settled tree warns as well")
    func writeVerbWarns() throws {
        let fixture = try CommandFixture(fixture: "font-missing.pen")
        let run = try fixture.run(
            "set", fixture.file.path, "Canvas/Label", "kind.content=Handgloves", "--as", "ana"
        )

        #expect(run.status == 0)
        #expect(run.stderr.contains(Self.missingFamily))
    }

    @Test("The warning is said once, not once per node in the family")
    func warningIsSaidOnce() throws {
        let fixture = try CommandFixture(fixture: "font-missing.pen")
        let run = try fixture.run("tree", fixture.file.path)

        let mentions = run.stderr
            .components(separatedBy: "\n")
            .filter { $0.contains(Self.missingFamily) }
        #expect(mentions.count == 1)
    }

    @Test("A file whose fonts all resolve says nothing at all")
    func silentWhenEveryFontResolves() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        let run = try fixture.run("tree", fixture.file.path)

        #expect(run.status == 0)
        #expect(run.stderr.isEmpty)
    }
}
