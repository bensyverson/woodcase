//
//  PenFlexFillMinimumTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A `fill_container` child with no room left on the main axis is 1 pt, not 0.
///
/// `flex-fill-squeeze.pen` is a column of 200-pt rows (padding 12, `alignItems: center`),
/// each a fixed rectangle beside one or two `fill_container` children, and one 100-pt-tall
/// column. Pen's layout of it (`scripts/pen-oracle`, 2026-09-28) gives every fill 1 pt
/// on the main axis — with the room overflowed by 27 (`fA2`) or 132 (`fE2`), exactly used
/// up (`fC2`, `fJ2`), left at 0.5 (`fD2`), on a frame (`fG2`), vertically (`fH2`) and two
/// fills side by side (`fF2`, `fF3`), and places the next child after that point. It is
/// the `fill-bar` of `layout-text-auto-overflow` (`tfG02`), which Woodcase made 0 wide
/// (leaf BpaSrF, `project/2026-09-28-pen-font-faces.md`, finding 3).
struct PenFlexFillMinimumTests {
    private static let fixtures = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    @Test("Every rect matches Pen's layout of the squeezed fills")
    func squeezedFillsMatchPen() throws {
        let document = try PenParser.parse(contentsOf: Self.fixtures.appendingPathComponent("flex-fill-squeeze.pen"))
        let expected = try JSONDecoder().decode(
            [String: PenRect].self,
            from: Data(contentsOf: Self.fixtures.appendingPathComponent("flex-fill-squeeze.layout.json"))
        )
        let actual = PenLayoutEngine.layout(document)
        for (id, pen) in expected.sorted(by: { $0.key < $1.key }) {
            #expect(actual[id] == pen, "\(id): Woodcase \(String(describing: actual[id])), Pen \(pen)")
        }
    }
}
