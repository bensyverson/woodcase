//
//  RemoveConnectorsCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// `woodcase rm` of a node takes the connectors attached to it, or to anything inside it,
/// in the same edit, names them in its answer, and `undo` brings both back.
///
/// `connectors-routes.pen`: `Card` holds `Dot`, the target of the `Nested` connection;
/// `Start` is the source of `Plain` and `Step`.
@Suite("woodcase rm takes attached connectors")
struct RemoveConnectorsCommandTests {
    /// Rewrites the fixture copy in the canonical on-disk form a transaction writes, so
    /// "byte-identical" is a meaningful thing to assert.
    private static func canonicalize(_ url: URL) throws {
        try PenParser.encodeForFile(PenParser.parse(Data(contentsOf: url))).write(to: url)
    }

    @Test("rm of a container removes the connector into it and names it")
    func containerNamesConnector() throws {
        let fixture = try CommandFixture(fixture: "connectors-routes.pen")
        let run = try fixture.run("rm", fixture.file.path, "Board/Card", "--as", "ana")

        #expect(run.status == 0, "rm failed: \(run.stderr)")
        #expect(run.stdout.contains("also removed 1 connector that ended on it or inside it: straight into a nested node, arrows both ends"), "\(run.stdout)")
        let probe = try PenFileProbe(fixture.file)
        #expect(probe.root(named: "straight into a nested node, arrows both ends") == nil)
        #expect(probe.root(named: "plain straight") != nil)
    }

    @Test("Undo after rm restores the node and its connectors byte for byte")
    func undoRestoresBoth() throws {
        let fixture = try CommandFixture(fixture: "connectors-routes.pen")
        try Self.canonicalize(fixture.file)
        let before = try Data(contentsOf: fixture.file)

        let remove = try fixture.run("rm", fixture.file.path, "Board/Start", "--as", "ana")
        #expect(remove.status == 0, "rm failed: \(remove.stderr)")
        #expect(remove.stdout.contains("2 connectors that ended on it or inside it: plain straight, elbow, arrow at the target"), "\(remove.stdout)")

        let undo = try fixture.run("undo", fixture.file.path, "--as", "ana")
        #expect(undo.status == 0)
        #expect(undo.stderr.isEmpty, "\(undo.stderr)")
        #expect(try Data(contentsOf: fixture.file) == before)
    }
}
