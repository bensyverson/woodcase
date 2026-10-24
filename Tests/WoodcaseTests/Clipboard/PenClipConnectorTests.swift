//
//  PenClipConnectorTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// ``PenClip/extract(nodeIDs:from:documentID:)`` carries every connector whose two ends
/// are both inside the copied nodes, selected or not, and none with an end outside (Ben's
/// ruling of 2026-10-23, Penumbra spec §11).
@MainActor
struct PenClipConnectorTests {
    @Test("Copying two connected nodes carries the connectors between them, and not one with an end outside")
    func carriesEnclosed() throws {
        let clip = try PenClip.extract(nodeIDs: ["CardA", "CardB"], from: ConnectorFixture.document())

        #expect(clip.contentIDs == ["CardA", "CardB"])
        #expect(clip.connectorIDs == ["KAB", "KTB"])
        let roots = clip.document.children.map(\.id)
        #expect(roots.prefix(4) == ["CardA", "CardB", "KAB", "KTB"])
        #expect(!roots.contains("KAC"))
        #expect(!roots.contains("KChip"))
        #expect(clip.document.variables?["line"] != nil, "the connector's stroke variable comes along")
        PenClipFixture.expectSelfContained(clip)
    }

    @Test("A carried connector's ends name the copies in the clip")
    func endsNameTheCopies() throws {
        let clip = try PenClip.extract(nodeIDs: ["CardA", "CardB"], from: ConnectorFixture.document())
        let roots = PenClipFixture.index(clip.document.children)

        #expect(ConnectorFixture.ends(of: roots["KAB"]) == ["CardA", "CardB"])
        #expect(ConnectorFixture.ends(of: roots["KTB"]) == ["Title", "CardB"])
    }

    @Test("A connector that is itself copied stays content, and is not carried twice")
    func selectedConnector() throws {
        let clip = try PenClip.extract(nodeIDs: ["CardA", "CardB", "KAB"], from: ConnectorFixture.document())

        #expect(clip.contentIDs == ["CardA", "CardB", "KAB"])
        #expect(clip.connectorIDs == ["KTB"])
        PenClipFixture.expectSelfContained(clip)
    }

    @Test("An end on a node drawn inside an instance follows the detached copy's id")
    func drawnEnd() throws {
        let clip = try PenClip.extract(nodeIDs: ["CardA", "Chip/Label"], from: ConnectorFixture.document())

        #expect(clip.connectorIDs == ["KChip"])
        let drawn = try #require(clip.contentIDs.last)
        #expect(drawn != "Chip/Label")
        let roots = PenClipFixture.index(clip.document.children)
        #expect(ConnectorFixture.ends(of: roots["KChip"]) == [drawn, "CardA"])
    }

    @Test("An end inside a copied instance keeps its instance path")
    func instanceEnd() throws {
        let clip = try PenClip.extract(nodeIDs: ["CardA", "Chip"], from: ConnectorFixture.document())

        #expect(clip.connectorIDs == ["KChip"])
        let roots = PenClipFixture.index(clip.document.children)
        #expect(ConnectorFixture.ends(of: roots["KChip"]) == ["Chip/Label", "CardA"])
    }

    @Test("Copying nodes no connector joins carries none")
    func none() throws {
        let clip = try PenClip.extract(nodeIDs: ["CardB", "CardC"], from: ConnectorFixture.document())

        #expect(clip.connectorIDs.isEmpty)
    }

    @Test("A clip written without connectorIDs decodes with none")
    func decodesWithout() throws {
        let json = #"{"contentIDs": ["R"], "document": {"version": "2.20", "children": [{"type": "rectangle", "id": "R"}]}}"#

        let clip = try JSONDecoder().decode(PenClip.self, from: Data(json.utf8))

        #expect(clip.connectorIDs.isEmpty)
        #expect(clip.contentIDs == ["R"])
    }

    @Test("A clip with carried connectors round-trips through JSON")
    func roundTrips() throws {
        let clip = try PenClip.extract(nodeIDs: ["CardA", "CardB"], from: ConnectorFixture.document())

        let decoded = try JSONDecoder().decode(PenClip.self, from: JSONEncoder().encode(clip))

        #expect(decoded == clip)
    }
}
