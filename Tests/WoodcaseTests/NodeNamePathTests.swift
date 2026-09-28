//
//  NodeNamePathTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct NodeNamePathTests {
    // MARK: - Helpers

    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/addressing.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    // MARK: - Formatting

    @Test("A named node's path is one segment per ancestor")
    func namedPath() throws {
        let doc = try makeDocument()
        #expect(doc.namePath(of: "Ttl01") == "Dashboard/Header/Title")
        #expect(doc.namePath(of: "Ttl02") == "Dashboard/Body/Title")
        #expect(doc.namePath(of: "Dash1") == "Dashboard")
    }

    @Test("A component's own subtree gets a path from the component root")
    func componentPath() throws {
        let doc = try makeDocument()
        #expect(doc.namePath(of: "Lbl01") == "Button/Label")
        #expect(doc.namePath(of: "Cnt01") == "BadgeBase/Count")
    }

    @Test("An unnamed node is rendered with the unnamed marker")
    func unnamedSegment() throws {
        let doc = try makeDocument()
        #expect(doc.namePath(of: "Unn01") == "Dashboard/Header/#Unn01")
    }

    @Test("A name containing a slash falls back to the marker so the path stays resolvable")
    func slashInName() throws {
        let doc = try makeDocument()
        #expect(doc.namePath(of: "Slsh1") == "Dashboard/Header/#Slsh1")
        #expect(try doc.resolve(doc.namePath(of: "Slsh1")) == .node(id: "Slsh1"))
    }

    @Test("An unknown id is rendered as its marker alone")
    func unknownID() throws {
        let doc = try makeDocument()
        #expect(doc.namePath(of: "nope1") == "#nope1")
    }

    // MARK: - Instance descendants

    @Test("An instance descendant's path continues through the component's names")
    func descendantPath() throws {
        let doc = try makeDocument()
        #expect(doc.namePath(ofDescendant: "Lbl01", in: "Nav01") == "Dashboard/Body/Nav/Label")
        #expect(doc.namePath(ofDescendant: "Bdg01/Cnt01", in: "Nav01") == "Dashboard/Body/Nav/Badge/Count")
    }

    @Test("A resolved address formats through the same entry point")
    func resolvedPath() throws {
        let doc = try makeDocument()
        #expect(doc.namePath(of: .node(id: "Ttl01")) == "Dashboard/Header/Title")
        #expect(
            doc.namePath(of: .instanceDescendant(refID: "Nav01", descendantKey: "Bdg01/Cnt01"))
                == "Dashboard/Body/Nav/Badge/Count"
        )
    }

    @Test("A descendant key that names nothing keeps its unresolved segments as markers")
    func unknownDescendantKey() throws {
        let doc = try makeDocument()
        #expect(doc.namePath(ofDescendant: "gone1", in: "Nav01") == "Dashboard/Body/Nav/#gone1")
    }

    // MARK: - Round trips

    @Test("Every node's name path resolves back to that node")
    func roundTripEveryNode() throws {
        let doc = try makeDocument()
        for nodeID in doc.allNodeIDs.sorted() {
            let path = doc.namePath(of: nodeID)
            #expect(try doc.resolve(path) == .node(id: nodeID), "\(nodeID) via \(path)")
        }
    }

    @Test("An instance descendant's name path resolves back to the same descendant")
    func roundTripDescendant() throws {
        let doc = try makeDocument()
        for key in ["Lbl01", "Bdg01", "Bdg01/Cnt01"] {
            let resolved = ResolvedNodeAddress.instanceDescendant(refID: "Nav01", descendantKey: key)
            #expect(try doc.resolve(doc.namePath(of: resolved)) == resolved, "key \(key)")
        }
    }
}
