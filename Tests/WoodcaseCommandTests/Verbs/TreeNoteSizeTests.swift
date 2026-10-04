//
//  TreeNoteSizeTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase tree` reports a note at the size it lays out at, so the rect an agent reads
/// is the one Penumbra hit-tests and the post-it look fills.
@Suite("woodcase tree sizes notes")
struct TreeNoteSizeTests {
    @Test("An unsized note is reported at 200×200")
    func unsizedNoteIs200() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let run = try fixture.run("tree", fixture.file.path)

        #expect(run.status == 0)
        let note = try #require(run.stdoutLines.first { $0.hasSuffix("NNote") })
        #expect(note.contains("200×200"), "the note's row reads \(note)")
    }

    @Test("set writes a note's width and height, and tree reports them")
    func setSizesANote() throws {
        let fixture = try CommandFixture(fixture: "every-node-type.pen")
        let set = try fixture.run(
            "set", fixture.file.path, "NNote", "kind.width=120", "kind.height=90", "kind.fontSize=18", "--as", "t"
        )
        #expect(set.status == 0, "set refused: \(set.stderr)")

        let run = try fixture.run("tree", fixture.file.path)
        let note = try #require(run.stdoutLines.first { $0.hasSuffix("NNote") })
        #expect(note.contains("120×90"), "the note's row reads \(note)")
    }
}
