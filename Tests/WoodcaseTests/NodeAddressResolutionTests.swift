//
//  NodeAddressResolutionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

@MainActor
struct NodeAddressResolutionTests {
    // MARK: - Helpers

    private func makeDocument() throws -> EditableDocument {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/addressing.pen")
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// Runs `body` and returns the ``EditingError`` it threw, recording an issue if it threw nothing.
    private func editingError(_ body: () throws -> some Any) -> EditingError? {
        do {
            _ = try body()
            Issue.record("expected an EditingError, but nothing was thrown")
            return nil
        } catch let error as EditingError {
            return error
        } catch {
            Issue.record("expected an EditingError, got \(error)")
            return nil
        }
    }

    /// Renames a node in place so a test can create a deliberate collision.
    private func rename(_ nodeID: String, to name: String, in doc: EditableDocument) throws {
        try doc.apply(.updateCommon(EditOperation.UpdateCommon(
            nodeID: nodeID, common: PenNodeCommon(name: name)
        )))
    }

    // MARK: - Ids

    @Test("A bare id resolves to that node")
    func bareID() throws {
        let doc = try makeDocument()
        #expect(try doc.resolve("Ttl01") == .node(id: "Ttl01"))
    }

    @Test("An id wins over a same-spelled name at any segment, not only a bare one")
    func idWinsMidPath() throws {
        let doc = try makeDocument()
        try rename("Body1", to: "Hdr01", in: doc)
        #expect(try doc.resolve("Dashboard/Hdr01") == .node(id: "Hdr01"))
        #expect(try doc.resolve("Dashboard/Body1") == .node(id: "Body1"))
    }

    @Test("A bare id wins over a same-spelled name")
    func idBeatsName() throws {
        let doc = try makeDocument()
        try rename("Ttl02", to: "Ttl01", in: doc)
        #expect(try doc.resolve("Ttl01") == .node(id: "Ttl01"))
    }

    @Test("An unnamed node resolves by id and by its unnamed marker")
    func unnamedNode() throws {
        let doc = try makeDocument()
        #expect(try doc.resolve("Unn01") == .node(id: "Unn01"))
        #expect(try doc.resolve("#Unn01") == .node(id: "Unn01"))
        #expect(try doc.resolve("Dashboard/Header/#Unn01") == .node(id: "Unn01"))
    }

    // MARK: - Name paths

    @Test("A full name path resolves to its leaf")
    func fullNamePath() throws {
        let doc = try makeDocument()
        #expect(try doc.resolve("Dashboard/Header/Title") == .node(id: "Ttl01"))
        #expect(try doc.resolve("Dashboard/Body/Title") == .node(id: "Ttl02"))
    }

    @Test("A path may start at any node, not only a root")
    func midTreeStart() throws {
        let doc = try makeDocument()
        #expect(try doc.resolve("Header/Title") == .node(id: "Ttl01"))
        #expect(try doc.resolve("Body/Nav") == .node(id: "Nav01"))
    }

    @Test("Segments must be consecutive parent to child")
    func segmentsAreConsecutive() throws {
        let doc = try makeDocument()
        let error = editingError { try doc.resolve("Dashboard/Title") }
        #expect(error?.isAddressNotFound == true)
    }

    @Test("A path may mix ids and names")
    func mixedSegments() throws {
        let doc = try makeDocument()
        #expect(try doc.resolve("Dash1/Header/Ttl01") == .node(id: "Ttl01"))
    }

    // MARK: - Instances

    @Test("A path through a ref resolves to an instance descendant")
    func instanceDescendant() throws {
        let doc = try makeDocument()
        #expect(
            try doc.resolve("Dashboard/Body/Nav/Label")
                == .instanceDescendant(refID: "Nav01", descendantKey: "Lbl01")
        )
    }

    @Test("A path through a nested ref uses Pen's prefixed descendant key")
    func nestedInstanceDescendant() throws {
        let doc = try makeDocument()
        #expect(
            try doc.resolve("Nav/Badge/Count")
                == .instanceDescendant(refID: "Nav01", descendantKey: "Bdg01/Cnt01")
        )
    }

    @Test("Descendant keys match the overrides the fixture already stores")
    func descendantKeysMatchFixture() throws {
        let doc = try makeDocument()
        guard case let .ref(refData) = try #require(doc.node(id: "Nav01")).kind else {
            Issue.record("Nav01 is not a ref")
            return
        }
        let keys = Set((refData.descendants ?? [:]).keys)
        let label = try #require(doc.resolve("Nav/Label").descendantKey)
        let count = try #require(doc.resolve("Nav/Badge/Count").descendantKey)
        #expect(keys.contains(label))
        #expect(keys.contains(count))
    }

    @Test("A ref at the end of a path is a plain node, not an instance descendant")
    func refTerminus() throws {
        let doc = try makeDocument()
        #expect(try doc.resolve("Dashboard/Body/Nav") == .node(id: "Nav01"))
    }

    @Test("The nested ref node itself is addressable as an instance descendant")
    func nestedRefNodeItself() throws {
        let doc = try makeDocument()
        #expect(
            try doc.resolve("Nav/Badge")
                == .instanceDescendant(refID: "Nav01", descendantKey: "Bdg01")
        )
    }

    @Test("The ref stands in for the component root, which is not a segment of its own")
    func componentRootIsNotASegment() throws {
        let doc = try makeDocument()
        let error = editingError { try doc.resolve("Nav/Button/Label") }
        #expect(error?.isAddressNotFound == true)
    }

    @Test("A component's own children stay addressable in the main tree")
    func componentDefinitionIsAddressable() throws {
        let doc = try makeDocument()
        #expect(try doc.resolve("Button/Label") == .node(id: "Lbl01"))
        #expect(try doc.resolve("Badge/Count") == .instanceDescendant(refID: "Bdg01", descendantKey: "Cnt01"))
    }

    // MARK: - Tags

    @Test("A tag resolves through the supplied map")
    func tagResolves() throws {
        let doc = try makeDocument()
        #expect(try doc.resolve("@hero", tags: ["hero": "Ttl01"]) == .node(id: "Ttl01"))
    }

    @Test("A tag that is not in the map is not found")
    func missingTag() throws {
        let doc = try makeDocument()
        let error = editingError { try doc.resolve("@hero", tags: [:]) }
        #expect(error == .addressNotFound(address: "@hero", nearMisses: []))
    }

    @Test("A tag pointing at a vanished node is not found")
    func tagPointsNowhere() throws {
        let doc = try makeDocument()
        let error = editingError { try doc.resolve("@hero", tags: ["hero": "gone1"]) }
        #expect(error == .addressNotFound(address: "@hero", nearMisses: []))
    }

    // MARK: - Ambiguity

    @Test("A duplicated name is ambiguous and lists every candidate by full path")
    func ambiguity() throws {
        let doc = try makeDocument()
        let error = editingError { try doc.resolve("Title") }
        #expect(error == .ambiguousAddress(address: "Title", candidates: [
            NodeAddressCandidate(id: "Ttl02", path: "Dashboard/Body/Title"),
            NodeAddressCandidate(id: "Ttl01", path: "Dashboard/Header/Title"),
        ]))
    }

    @Test("An ambiguous instance path lists candidates by their id-path address")
    func ambiguousInstanceCandidate() throws {
        let doc = try makeDocument()
        try rename("Bdg01", to: "Label", in: doc)
        let error = editingError { try doc.resolve("Nav/Label") }
        #expect(error == .ambiguousAddress(address: "Nav/Label", candidates: [
            NodeAddressCandidate(id: "Nav01/Bdg01", path: "Dashboard/Body/Nav/Label"),
            NodeAddressCandidate(id: "Nav01/Lbl01", path: "Dashboard/Body/Nav/Label"),
        ]))
    }

    @Test("A candidate's id-path address resolves back to the same target")
    func candidateAddressesResolve() throws {
        let doc = try makeDocument()
        try rename("Bdg01", to: "Label", in: doc)
        guard case let .ambiguousAddress(_, candidates)? =
            editingError({ try doc.resolve("Nav/Label") })
        else { return }

        #expect(try doc.resolve(candidates[0].id)
            == .instanceDescendant(refID: "Nav01", descendantKey: "Bdg01"))
        #expect(try doc.resolve(candidates[1].id)
            == .instanceDescendant(refID: "Nav01", descendantKey: "Lbl01"))
    }

    // MARK: - Misses

    @Test("A miss names the nodes whose leaf name matches")
    func nearMisses() throws {
        let doc = try makeDocument()
        let error = editingError { try doc.resolve("Dashboard/Footer/Title") }
        #expect(error == .addressNotFound(address: "Dashboard/Footer/Title", nearMisses: [
            NodeAddressCandidate(id: "Ttl02", path: "Dashboard/Body/Title"),
            NodeAddressCandidate(id: "Ttl01", path: "Dashboard/Header/Title"),
        ]))
    }

    @Test("A miss with no same-named node anywhere lists no near misses")
    func noNearMisses() throws {
        let doc = try makeDocument()
        let error = editingError { try doc.resolve("Sidebar/Widget") }
        #expect(error == .addressNotFound(address: "Sidebar/Widget", nearMisses: []))
    }

    @Test("A malformed address is not found")
    func malformedAddress() throws {
        let doc = try makeDocument()
        let error = editingError { try doc.resolve("Dashboard//Title") }
        #expect(error == .addressNotFound(address: "Dashboard//Title", nearMisses: []))
    }

    // MARK: - Resolved target accessors

    @Test("A resolved address exposes the node that stores the edit")
    func targetIDs() throws {
        let doc = try makeDocument()
        #expect(try doc.resolve("Ttl01").targetID == "Ttl01")
        #expect(try doc.resolve("Ttl01").descendantKey == nil)
        #expect(try doc.resolve("Nav/Label").targetID == "Nav01")
        #expect(try doc.resolve("Nav/Label").descendantKey == "Lbl01")
    }
}

private extension EditingError {
    var isAddressNotFound: Bool {
        if case .addressNotFound = self { return true }
        return false
    }
}
