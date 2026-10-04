//
//  RemoveDetachUndoTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase rm --detach` logs a detach per instance before the delete, and `undo`
/// replays the logged inverses. Each detach's inverse has to remove the expanded
/// subtree as well as restore the ref, or the undo leaves both behind.
@Suite("woodcase rm --detach, then undo")
struct RemoveDetachUndoTests {
    /// Rewrites the fixture copy in the canonical on-disk form a transaction writes,
    /// so "byte-identical" is a meaningful thing to assert.
    private static func canonicalize(_ url: URL) throws {
        try PenParser.encodeForFile(PenParser.parse(Data(contentsOf: url))).write(to: url)
    }

    @Test("Undo after rm --detach restores the file byte for byte")
    func undoRestoresTheBytes() throws {
        let fixture = try CommandFixture(fixture: "batch.pen")
        try Self.canonicalize(fixture.file)
        let before = try Data(contentsOf: fixture.file)

        let remove = try fixture.run("rm", fixture.file.path, "Component", "--detach", "--as", "ana")
        #expect(remove.status == 0)
        #expect(try Data(contentsOf: fixture.file) != before)

        let undo = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(undo.status == 0)
        #expect(undo.stderr.isEmpty)
        #expect(try Data(contentsOf: fixture.file) == before)
    }
}
