//
//  ConnectorCarryCommandTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

/// The verbs that ungroup, copy and paste name the connectors they take or carry.
///
/// `connectors-group.pen`: `Board` holds `Pair`, a group of `G1` and `G2`, and `Lone`;
/// `KG` ("group link") joins `Pair` to `Lone`, and `K12` ("inner link") joins `G1` to `G2`.
/// `connectors-instance.pen`: `Board` holds `Chip`, an instance of `Comp` (whose child is
/// `Label`), and `Lone`; `KChip` joins `Chip` to `Lone`, and `KLabel` joins `Chip/Label` to
/// `Lone`.
@Suite("woodcase ungroup, clip and paste name their connectors")
struct ConnectorCarryCommandTests {
    @Test("ungroup removes the connector attached to the group and names it")
    func ungroupNamesConnector() throws {
        let fixture = try CommandFixture(fixture: "connectors-group.pen")

        let run = try fixture.run("ungroup", fixture.file.path, "Board/Pair", "--as", "ana")

        #expect(run.status == 0, "\(run.stderr)")
        #expect(run.stdoutLines.first == "ungrouped G1, G2")
        #expect(run.stdout.contains("also removed 1 connector attached to Pair: group link"), "\(run.stdout)")
        let document = try EditableDocument(from: PenParser.parse(Data(contentsOf: fixture.file)))
        #expect(document.node(id: "KG") == nil)
        #expect(document.node(id: "K12") != nil)
    }

    @Test("rm --detach keeps the connectors attached to the instance it detaches, and into it")
    func removeDetachKeepsConnectors() throws {
        let fixture = try CommandFixture(fixture: "connectors-instance.pen")

        let run = try fixture.run("rm", fixture.file.path, "Comp", "--detach", "--as", "ana")

        #expect(run.status == 0, "\(run.stderr)")
        let document = try EditableDocument(from: PenParser.parse(Data(contentsOf: fixture.file)))
        for id in ["KChip", "KLabel"] {
            guard case let .connection(data)? = document.node(id: id)?.kind else {
                Issue.record("\(id) is gone")
                continue
            }
            #expect(document.node(id: data.source.path) != nil, "\(id) dangles: \(data.source.path)")
        }
        guard case let .connection(label)? = document.node(id: "KLabel")?.kind else { return }
        #expect(document.node(id: label.source.path)?.common.name == "Label")
    }

    @Test("ungroup --json lists the connectors removed")
    func ungroupJSON() throws {
        let fixture = try CommandFixture(fixture: "connectors-group.pen")

        let run = try fixture.run("ungroup", fixture.file.path, "Board/Pair", "--as", "ana", "--json")

        #expect(run.status == 0, "\(run.stderr)")
        let report = try JSONDecoder().decode(UngroupCommand.Report.self, from: Data(run.stdout.utf8))
        #expect(report.deletedConnectors == ["KG"])
    }

    @Test("clip carries the connector between the copied nodes, and paste attaches it to the copies")
    func clipAndPaste() throws {
        let fixture = try CommandFixture(fixture: "connectors-group.pen")
        let copy = try fixture.run("clip", fixture.file.path, "Board/Pair/G1", "Board/Pair/G2", "--json")
        #expect(copy.status == 0, "\(copy.stderr)")
        let clip = try JSONDecoder().decode(PenClip.self, from: Data(copy.stdout.utf8))
        #expect(clip.connectorIDs == ["K12"])
        let url = fixture.root.appendingPathComponent("clip.json")
        try Data(copy.stdout.utf8).write(to: url)

        let paste = try fixture.run("paste", fixture.file.path, url.path, "--as", "ana", "--json")

        #expect(paste.status == 0, "\(paste.stderr)")
        let report = try JSONDecoder().decode(PasteCommand.Report.self, from: Data(paste.stdout.utf8))
        let connector = try #require(report.insertedConnectorIDs?.first)
        let document = try EditableDocument(from: PenParser.parse(Data(contentsOf: fixture.file)))
        guard case let .connection(data)? = document.node(id: connector)?.kind else {
            Issue.record("no pasted connector")
            return
        }
        #expect([data.source.path, data.target.path] == report.insertedRootIDs)
    }

    @Test("paste names the connectors it carried")
    func pasteText() throws {
        let fixture = try CommandFixture(fixture: "connectors-group.pen")
        let copy = try fixture.run("clip", fixture.file.path, "Board/Pair/G1", "Board/Pair/G2", "--json")
        let url = fixture.root.appendingPathComponent("clip.json")
        try Data(copy.stdout.utf8).write(to: url)

        let paste = try fixture.run("paste", fixture.file.path, url.path, "--as", "ana")

        #expect(paste.status == 0, "\(paste.stderr)")
        #expect(paste.stdoutLines.contains { $0.hasPrefix("attached connectors ") }, "\(paste.stdout)")
    }
}
