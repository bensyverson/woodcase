//
//  DocumentLinterOverlapTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `artboard-overlap`: one finding per pair of roots whose settled rects intersect.
@MainActor
struct DocumentLinterOverlapTests {
    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func document(_ name: String) throws -> EditableDocument {
        guard let url = Bundle.module.url(
            forResource: (name as NSString).deletingPathExtension,
            withExtension: "pen",
            subdirectory: "Fixtures/lint"
        ) else {
            throw FixtureLoadError.notFound(name)
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// A document of plain 100×100 root frames at the given origins.
    private func roots(_ origins: [(id: String, name: String, x: Double, y: Double)]) -> EditableDocument {
        EditableDocument(from: PenDocument(children: origins.map { origin in
            PenNode(
                id: origin.id,
                common: PenNodeCommon(name: origin.name, x: .literal(origin.x), y: .literal(origin.y)),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(100), height: .fixed(100), layout: PenLayoutDirection.none
                ))
            )
        }))
    }

    private func overlapFindings(_ document: EditableDocument) throws -> [LintFinding] {
        try DocumentLinter.findings(in: document).filter { $0.check == .artboardOverlap }
    }

    // MARK: - The check

    @Test("The check is a warning, and its id is artboard-overlap")
    func checkIsAWarning() {
        #expect(LintCheck.artboardOverlap.rawValue == "artboard-overlap")
        #expect(LintCheck.artboardOverlap.severity == .warning)
        #expect(!LintCheck.artboardOverlap.summary.isEmpty)
    }

    // MARK: - Findings

    @Test("Two overlapping roots are one finding, named on the later of the two")
    func overlappingRootsAreOneFinding() throws {
        let findings = try overlapFindings(document("artboard-overlap-trips.pen"))
        #expect(findings.count == 1)
        let finding = try #require(findings.first)
        #expect(finding.nodeID == "Chk01")
        #expect(finding.path == "Checkout")
        #expect(finding.severity == .warning)
    }

    @Test("The finding names both roots by name, id and rect")
    func findingNamesBothRoots() throws {
        let message = try #require(try overlapFindings(document("artboard-overlap-trips.pen")).first?.message)
        #expect(message.contains("Home"))
        #expect(message.contains("Home1"))
        #expect(message.contains("0,0 200×100"))
        #expect(message.contains("150,40 200×100"))
    }

    @Test("The finding suggests the first x that clears the other root by the margin")
    func findingSuggestsAClearingX() throws {
        let message = try #require(try overlapFindings(document("artboard-overlap-trips.pen")).first?.message)
        // Home ends at x 200; the margin is 100, so 300 is the first clear x.
        #expect(message.contains("woodcase set <file> Chk01 common.x=300"))
    }

    @Test("Roots that only share an edge do not overlap")
    func touchingRootsAreClean() throws {
        #expect(try overlapFindings(document("artboard-overlap-clean.pen")).isEmpty)
    }

    @Test("Roots far apart do not overlap")
    func separatedRootsAreClean() throws {
        #expect(try overlapFindings(document("fill-distribution.pen")).isEmpty)
    }

    @Test("Every overlapping pair is reported, not only the first")
    func everyPairIsReported() throws {
        // Three roots stacked 50 apart on a 100×100 grid: A–B, A–C and B–C all intersect.
        let findings = try overlapFindings(roots([
            (id: "Aaa01", name: "A", x: 0, y: 0),
            (id: "Bbb01", name: "B", x: 50, y: 0),
            (id: "Ccc01", name: "C", x: 25, y: 50),
        ]))
        #expect(findings.count == 3)
        #expect(findings.map(\.nodeID) == ["Bbb01", "Ccc01", "Ccc01"])
    }

    @Test("A single root cannot overlap anything")
    func oneRootIsAlwaysClean() throws {
        #expect(try overlapFindings(roots([(id: "Aaa01", name: "A", x: 0, y: 0)])).isEmpty)
    }

    @Test("A lint scoped to one root reports no overlap, because it lists no other root")
    func scopedLintReportsNoOverlap() throws {
        let findings = try DocumentLinter.findings(in: document("artboard-overlap-trips.pen"), root: "Checkout")
        #expect(!findings.contains { $0.check == .artboardOverlap })
    }

    @Test("Findings come in document order, on the root a reader would move")
    func findingsAreInDocumentOrder() throws {
        let findings = try DocumentLinter.findings(in: roots([
            (id: "Aaa01", name: "A", x: 0, y: 0),
            (id: "Bbb01", name: "B", x: 50, y: 0),
            (id: "Ccc01", name: "C", x: 400, y: 0),
            (id: "Ddd01", name: "D", x: 450, y: 0),
        ]))
        #expect(findings.map(\.nodeID) == ["Bbb01", "Ddd01"])
    }
}
