//
//  RootRectsEquivalenceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Proves that ``RootOverlap/roots(in:textMeasurer:)`` answers exactly what a full settle
/// does, over every fixture in the repository.
///
/// The roots-only measurement exists to be cheap — a fixed-size root is never laid out,
/// a content-sized one is laid out alone — and cheap is worthless if it is wrong: a rect
/// off by a point is an overlap warning missed or invented. So the reference here is the
/// most expensive answer there is, ``TreeView``'s depth-0 rows over a whole
/// ``SettledTree``, which is also exactly what `lint`'s `artboard-overlap` check reads.
/// The comparison is exact, not approximate: both sides run the same layout over the same
/// nodes, so any difference at all is a divergence in *which* nodes they laid out.
///
/// No fixture has a rotated root, so the second test turns every root of every fixture
/// by 30° and compares again.
@Suite("Root rects equal a full settle's")
struct RootRectsEquivalenceTests {
    /// What kinds of root the comparisons covered, so a corpus that stopped exercising
    /// one path fails rather than passing vacuously.
    struct Coverage {
        var documents = 0
        var fixedSize = 0
        var contentSized = 0
        var instances = 0
        var rotated = 0
    }

    @Test("every root of every fixture measures exactly as a full settle places it")
    func everyFixture() throws {
        var coverage = Coverage()
        for url in try Self.fixtureURLs() {
            guard let parsed = try? PenParser.parse(Data(contentsOf: url)) else { continue }
            try Self.compare(parsed, at: url, coverage: &coverage)
        }
        Self.expectCoverage(coverage, rotated: false)
    }

    @Test("every root of every fixture, turned 30°, measures exactly as a full settle places it")
    func everyFixtureRotated() throws {
        var coverage = Coverage()
        for url in try Self.fixtureURLs() {
            guard var parsed = try? PenParser.parse(Data(contentsOf: url)) else { continue }
            for index in parsed.children.indices {
                parsed.children[index].common.rotation = .literal(30)
            }
            try Self.compare(parsed, at: url, coverage: &coverage)
        }
        Self.expectCoverage(coverage, rotated: true)
    }

    // MARK: - Helpers

    /// Compares one document's roots both ways and records what it covered.
    private static func compare(_ parsed: PenDocument, at url: URL, coverage: inout Coverage) throws {
        let document = PenFileTransaction.editableDocument(from: parsed, at: url, fonts: nil)
        let reference = try TreeView.rows(of: document, depth: 0).compactMap { row in
            row.rect.map { RootOverlap.Root(id: row.id, name: row.name, rect: $0) }
        }
        let measured = RootOverlap.roots(in: document)
        #expect(
            measured.map(\.id) == reference.map(\.id),
            "\(url.lastPathComponent): the roots measured are not the roots a full settle places"
        )
        for (mine, settled) in zip(measured, reference) where mine.id == settled.id {
            #expect(
                mine.rect == settled.rect,
                "\(url.lastPathComponent) root \(mine.id): \(mine.rect) ≠ settled \(settled.rect)"
            )
        }

        coverage.documents += 1
        for root in reference {
            guard let node = document.nodes[root.id] else { continue }
            if node.common.rotation?.literalValue ?? 0 != 0 { coverage.rotated += 1 }
            if case .ref = node.kind {
                coverage.instances += 1
            } else if case .fixed = PenLayoutEngine.widthSizing(of: node),
                      case .fixed = PenLayoutEngine.heightSizing(of: node)
            {
                coverage.fixedSize += 1
            } else {
                coverage.contentSized += 1
            }
        }
    }

    /// Fails when the corpus stopped exercising one of the measurement's paths.
    private static func expectCoverage(_ coverage: Coverage, rotated: Bool) {
        #expect(coverage.documents > 100, "Only \(coverage.documents) fixtures parsed.")
        #expect(coverage.fixedSize > 0, "No fixed-size root was compared.")
        #expect(coverage.contentSized > 0, "No content-sized root was compared.")
        #expect(coverage.instances > 0, "No instance root was compared.")
        if rotated {
            #expect(coverage.rotated > 0, "No rotated root was compared.")
        }
    }

    /// Every `.pen` file under the bundled fixtures, in a stable order.
    private static func fixtureURLs() throws -> [URL] {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let walk = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        let urls = (walk?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "pen" }
        return urls.sorted { $0.path < $1.path }
    }
}
