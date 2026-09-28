//
//  ClipToleranceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The one tolerance ``TreeRow/clipTolerance`` names, from both sides: the flag a tree
/// read prints and the finding a lint reports.
///
/// The regression is a row of `fill_container` bars whose widths divide their frame
/// exactly. The last bar's right edge lands on the frame's own edge in exact
/// arithmetic and a few parts in 10¹³ past it in binary floating point, which read as
/// a clipped design until the comparison gained a tolerance.
@MainActor
struct ClipToleranceTests {
    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func distributionDocument() throws -> EditableDocument {
        guard let url = Bundle.module.url(
            forResource: "fill-distribution", withExtension: "pen", subdirectory: "Fixtures/lint"
        ) else {
            throw FixtureLoadError.notFound("fill-distribution.pen")
        }
        return try EditableDocument(from: PenParser.parse(contentsOf: url))
    }

    /// A frame whose single child overflows its right edge by `overflow` points.
    private func overflowing(by overflow: Double) -> EditableDocument {
        EditableDocument(from: PenDocument(children: [
            PenNode(
                id: "Rt001",
                common: PenNodeCommon(name: "Root", x: .literal(0), y: .literal(0)),
                kind: .frame(PenNode.FrameData(
                    width: .fixed(200),
                    height: .fixed(100),
                    layout: PenLayoutDirection.none,
                    children: [
                        PenNode(
                            id: "Ovr01",
                            common: PenNodeCommon(name: "Overflows", x: .literal(0), y: .literal(0)),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(200 + overflow),
                                height: .fixed(10)
                            ))
                        ),
                    ]
                ))
            ),
        ]))
    }

    // MARK: - The tolerance itself

    @Test("The tolerance is a hundredth of a point, well under anything a design means")
    func toleranceIsOneHundredthOfAPoint() {
        #expect(TreeRow.clipTolerance == 0.01)
    }

    // MARK: - The distribution that used to trip

    @Test("59 fill_container bars at gap 1 in a 350-wide frame carry no clip flag")
    func gapOneDistributionIsUnclipped() throws {
        let rows = try TreeView.rows(of: distributionDocument(), root: "Gap One")
        #expect(rows.count == 60)
        #expect(rows.allSatisfy { $0.clip == .none })
    }

    @Test("60 fill_container bars at gap 2 in a 350-wide frame carry no clip flag")
    func gapTwoDistributionIsUnclipped() throws {
        let rows = try TreeView.rows(of: distributionDocument(), root: "Gap Two")
        #expect(rows.count == 61)
        #expect(rows.allSatisfy { $0.clip == .none })
    }

    @Test("Neither distribution is a clipped finding")
    func distributionsProduceNoClippedFinding() throws {
        let findings = try DocumentLinter.findings(in: distributionDocument())
        #expect(!findings.contains { $0.check == .clipped })
    }

    @Test("The last bar really does land on the frame's edge, so the tolerance is what saves it")
    func theLastBarLandsOnTheEdge() throws {
        let document = try distributionDocument()
        let rows = try TreeView.rows(of: document, root: "Gap One")
        let last = try #require(rows.last?.rect)
        #expect(abs(last.x + last.width - 350) < TreeRow.clipTolerance)
    }

    // MARK: - What still clips

    @Test("A half-point overflow is still partial clipping")
    func halfAPointStillClips() throws {
        let rows = try TreeView.rows(of: overflowing(by: 0.5))
        #expect(rows.last?.clip == .partial)

        let findings = try DocumentLinter.findings(in: overflowing(by: 0.5))
        #expect(findings.contains { $0.check == .clipped })
    }

    @Test("An overflow just past the tolerance still clips; one just inside it does not")
    func theToleranceIsTheBoundary() throws {
        let past = try TreeView.rows(of: overflowing(by: TreeRow.clipTolerance * 2))
        #expect(past.last?.clip == .partial)

        let inside = try TreeView.rows(of: overflowing(by: TreeRow.clipTolerance / 2))
        #expect(inside.last?.clip == TreeRow.Clip.none)
    }
}
