//
//  RootOverlapIntroducedTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The before-and-after that says which overlaps a write *created*.
///
/// The diff used to live in the command core, so only a verb could take it; a script host
/// or an editor holding the same document had to write its own. It is the library's now,
/// beside the geometry it compares, and ``RootOverlap/finding(in:file:)`` renders the one
/// line every caller prints.
@MainActor
struct RootOverlapIntroducedTests {
    /// A document of 100×100 root frames at the given origins.
    private func document(_ origins: [(id: String, x: Double, y: Double)]) -> EditableDocument {
        EditableDocument(from: PenDocument(children: origins.map { origin in
            PenNode(
                id: origin.id,
                common: PenNodeCommon(
                    name: "Root \(origin.id)", x: .literal(origin.x), y: .literal(origin.y)
                ),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(100), height: .fixed(100), layout: PenLayoutDirection.none
                ))
            )
        }))
    }

    /// Slides one root to a new x.
    private func slide(_ id: String, to x: Double, in document: EditableDocument) throws {
        try document.apply(.setProperties(EditOperation.SetProperties(
            nodeID: id, properties: ["common.x": .double(x)]
        )))
    }

    // MARK: - The pairs

    @Test("A clean document has no pairs, and an overlapping one has the pair by id")
    func pairsAreIdentity() throws {
        let clean = document([(id: "Aaa01", x: 0, y: 0), (id: "Bbb01", x: 300, y: 0)])
        #expect(RootOverlap.pairs(in: clean).isEmpty)

        try slide("Bbb01", to: 50, in: clean)
        #expect(RootOverlap.pairs(in: clean) == [RootOverlap.Pair("Aaa01", "Bbb01")])
    }

    // MARK: - What a write introduced

    @Test("An overlap a write created is reported")
    func aNewOverlapIsIntroduced() throws {
        let doc = document([(id: "Aaa01", x: 0, y: 0), (id: "Bbb01", x: 300, y: 0)])
        let before = RootOverlap.pairs(in: doc)

        try slide("Bbb01", to: 50, in: doc)

        let introduced = RootOverlap.introduced(since: before, in: doc)
        #expect(introduced.map(\.pair) == [RootOverlap.Pair("Aaa01", "Bbb01")])
    }

    @Test("An overlap that was already there is not reported again")
    func anOldOverlapIsNotIntroduced() throws {
        let doc = document([(id: "Aaa01", x: 0, y: 0), (id: "Bbb01", x: 50, y: 0)])
        let before = RootOverlap.pairs(in: doc)

        try slide("Bbb01", to: 60, in: doc)

        #expect(RootOverlap.introduced(since: before, in: doc).isEmpty)
    }

    @Test("A break the same run repaired is not reported")
    func aRepairIsNotIntroduced() throws {
        let doc = document([(id: "Aaa01", x: 0, y: 0), (id: "Bbb01", x: 300, y: 0)])
        let before = RootOverlap.pairs(in: doc)

        try slide("Bbb01", to: 50, in: doc)
        try slide("Bbb01", to: 300, in: doc)

        #expect(RootOverlap.introduced(since: before, in: doc).isEmpty)
    }

    // MARK: - The line

    @Test("The finding is the artboard-overlap line every caller prints")
    func theFindingRendersTheLine() throws {
        let doc = document([(id: "Aaa01", x: 0, y: 0), (id: "Bbb01", x: 300, y: 0)])
        let before = RootOverlap.pairs(in: doc)
        try slide("Bbb01", to: 50, in: doc)

        let overlap = try #require(RootOverlap.introduced(since: before, in: doc).first)
        let finding = overlap.finding(in: doc, file: "design.pen")

        #expect(finding.check == .artboardOverlap)
        #expect(finding.nodeID == "Bbb01")
        #expect(finding.path == doc.namePath(of: "Bbb01"))
        #expect(
            LintFormatter.text([finding]) == "warning artboard-overlap  Root Bbb01 (Bbb01)  "
                + "50,0 100×100 overlaps Root Aaa01 (Aaa01) 0,0 100×100. Artboards do not "
                + "overlap: run `woodcase set design.pen Bbb01 common.x=200` to put it clear "
                + "by 100pt."
        )
    }
}
