//
//  PenLayoutTurnedFillTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins how a turned `fill_container` flex child is sized: Pen fills the child's
/// *unturned* box — the main-axis share, or the container's inner cross size — then turns
/// it, and the container allocates, aligns and fits the bounds of the turned result.
///
/// `flex-turned-fill.pen` is one board of rows, each `[A 60×40, B, C 60×40]` with
/// padding 10, gap 10 and `alignItems: start`. Every expectation below is worked by hand
/// from that rule (cos 30° = 0.866025, sin 30° = ½) and agrees with Pen's *settled* layout
/// (`pen interactive`, every row's `gap` nudged and restored, 2026-09-28; see
/// `scripts/pen-settle`). It is not Pen's first layout after load: that pass measures a
/// turned child whose height is not resolved yet at height 0, and Woodcase keeps the
/// converged answer instead (PenInteroperability.md, *Kept divergences*).
struct PenLayoutTurnedFillTests {
    /// One node's expected rect, and the unturned size its rect must carry.
    struct Expectation: CustomTestStringConvertible {
        let id: String
        let rect: (x: Double, y: Double, width: Double, height: Double)
        let unturned: (width: Double, height: Double)?
        let why: String

        var testDescription: String {
            "\(id): \(why)"
        }
    }

    private static func layout() throws -> [String: PenRect] {
        let url = try #require(Bundle.module.url(
            forResource: "flex-turned-fill", withExtension: "pen", subdirectory: "Fixtures"
        ))
        return try PenLayoutEngine.layout(PenParser.parse(contentsOf: url))
    }

    private static func check(_ expected: Expectation, in rects: [String: PenRect]) throws {
        let rect = try #require(rects[expected.id], "\(expected.id) was not laid out")
        let tolerance = 0.001
        let actual = [rect.x, rect.y, rect.width, rect.height]
        let wanted = [expected.rect.x, expected.rect.y, expected.rect.width, expected.rect.height]
        #expect(
            zip(actual, wanted).allSatisfy { abs($0 - $1) < tolerance },
            "\(expected.id): \(rect), expected \(expected.rect)"
        )
        if let unturned = expected.unturned {
            let size = try #require(rect.unturnedSize, "\(expected.id) carries no unturned size")
            #expect(
                abs(size.width - unturned.width) < tolerance && abs(size.height - unturned.height) < tolerance,
                "\(expected.id) unturned \(size), expected \(unturned)"
            )
        } else {
            #expect(rect.unturnedSize == nil, "\(expected.id) is not turned, yet carries \(String(describing: rect.unturnedSize))")
        }
    }

    // MARK: - Main axis

    static let mainAxis: [Expectation] = [
        Expectation(id: "h1b", rect: (80, 10, 141.24356, 104.64102), unturned: (140, 40),
                    why: "row 300: the 140 share fills the unturned width; its 30° bounds are the slot"),
        Expectation(id: "h1c", rect: (231.24356, 10, 60, 40), unturned: nil,
                    why: "the next sibling starts past the turned slot"),
        Expectation(id: "h1", rect: (20, 20, 300, 124.64102), unturned: nil,
                    why: "a fit_content row height takes the turned slot's height"),
        Expectation(id: "h2b", rect: (80, 10, 40, 140), unturned: (140, 40),
                    why: "at 90° the 140 share becomes the slot's height"),
        Expectation(id: "h2c", rect: (130, 10, 60, 40), unturned: nil,
                    why: "the sibling follows a 40-wide slot"),
        Expectation(id: "v1b", rect: (10, 60, 141.96152, 185.88457), unturned: (60, 180),
                    why: "column 300: the 180 share fills the unturned height"),
        Expectation(id: "v1c", rect: (10, 255.88457, 60, 40), unturned: nil,
                    why: "the next sibling starts below the turned slot"),
        Expectation(id: "v1", rect: (20, 1089.28204, 161.96152, 300), unturned: nil,
                    why: "a fit_content column width takes the turned slot's width"),
        Expectation(id: "v2b", rect: (10, 60, 180, 60), unturned: (60, 180),
                    why: "at 90° the 180 share becomes the slot's width"),
        Expectation(id: "v2c", rect: (10, 130, 60, 40), unturned: nil,
                    why: "the sibling follows a 60-tall slot"),
    ]

    @Test("A turned main-axis fill child fills its unturned size; its turned bounds are its slot", arguments: mainAxis)
    func mainAxisFill(_ expected: Expectation) throws {
        try Self.check(expected, in: Self.layout())
    }

    // MARK: - Cross axis

    static let crossAxis: [Expectation] = [
        Expectation(id: "h3b", rect: (80, 10, 100, 60), unturned: (60, 100),
                    why: "row height 120: the inner 100 fills the unturned height, laid out turned 90°"),
        Expectation(id: "h3c", rect: (190, 10, 60, 40), unturned: nil,
                    why: "the sibling follows a 100-wide slot"),
        Expectation(id: "h4b", rect: (80, 10, 101.96152, 116.60254), unturned: (60, 100),
                    why: "the same at 30°: the slot is the turned 60×100 box's bounds"),
        Expectation(id: "h4c", rect: (191.96152, 10, 60, 40), unturned: nil,
                    why: "the sibling follows the turned slot"),
        Expectation(id: "v3b", rect: (10, 60, 40, 100), unturned: (100, 40),
                    why: "column width 120: the inner 100 fills the unturned width, laid out turned 90°"),
        Expectation(id: "v3c", rect: (10, 170, 60, 40), unturned: nil,
                    why: "the sibling follows a 100-tall slot"),
        Expectation(id: "v4b", rect: (10, 60, 106.60254, 84.64102), unturned: (100, 40),
                    why: "the same at 30°"),
        Expectation(id: "v4", rect: (20, 1969.28204, 120, 204.64102), unturned: nil,
                    why: "a fit_content column height takes the turned slot's height"),
        Expectation(id: "h8b", rect: (80, 10, 171.24356, 156.60254), unturned: (140, 100),
                    why: "filling both axes: the 140 share and the inner 100 fill the unturned box"),
        Expectation(id: "h8c", rect: (261.24356, 10, 60, 40), unturned: nil,
                    why: "the sibling follows the turned slot"),
    ]

    @Test("A turned cross-axis fill child fills its unturned size; its turned bounds are its slot", arguments: crossAxis)
    func crossAxisFill(_ expected: Expectation) throws {
        try Self.check(expected, in: Self.layout())
    }

    // MARK: - Flip

    static let flipped: [Expectation] = [
        Expectation(id: "h5b", rect: (80, 10, 140, 40), unturned: nil, why: "a flipped main-axis fill is an unflipped one"),
        Expectation(id: "h5c", rect: (230, 10, 60, 40), unturned: nil, why: "and moves nothing"),
        Expectation(id: "h6b", rect: (80, 10, 60, 100), unturned: nil, why: "a flipped cross-axis fill is an unflipped one"),
        Expectation(id: "h6c", rect: (150, 10, 60, 40), unturned: nil, why: "and moves nothing"),
    ]

    @Test("Flipping a fill child changes nothing in layout", arguments: flipped)
    func flipOnly(_ expected: Expectation) throws {
        try Self.check(expected, in: Self.layout())
    }

    // MARK: - Pen's first pass, not kept

    /// Pen's first layout after load fits widths before heights, so a turned child whose
    /// height is unresolved at that point is measured at height 0. Its first-pass answers
    /// (row widths h3 160, h4 211.96, h7 211.96, e1 160, e2 211.96; column widths v1 80,
    /// v2 80) change on any relayout to these, which Woodcase keeps.
    static let converged: [Expectation] = [
        Expectation(id: "h3", rect: (20, 344.64102, 260, 120), unturned: nil,
                    why: "cross fill at 90° in a fixed-height row: 260 wide, not Pen's first-pass 160"),
        Expectation(id: "h4", rect: (20, 484.64102, 261.96152, 120), unturned: nil,
                    why: "the same at 30°: not Pen's first-pass 211.96"),
        Expectation(id: "h7f", rect: (80, 10, 71.96152, 64.64102), unturned: (60, 40),
                    why: "a turned fit_content frame takes its turned bounds"),
        Expectation(id: "h7", rect: (20, 844.64102, 231.96152, 84.64102), unturned: nil,
                    why: "around a turned fit_content frame: not Pen's first-pass 211.96"),
        Expectation(id: "v2", rect: (20, 1409.28204, 200, 300), unturned: nil,
                    why: "around a 90° main fill: not Pen's first-pass 80"),
        Expectation(id: "e1b", rect: (80, 10, 40, 60), unturned: (60, 40),
                    why: "fit_content row: the cross fill takes the inner 40 its siblings set, then turns"),
        Expectation(id: "e1", rect: (20, 2193.92306, 200, 60), unturned: nil,
                    why: "a cross fill adds nothing to its row's height, and its turned width to its row's width"),
        Expectation(id: "e1c", rect: (130, 10, 60, 40), unturned: nil, why: "the sibling follows a 40-wide slot"),
        Expectation(id: "e2b", rect: (80, 10, 71.96152, 64.64102), unturned: (60, 40), why: "the same at 30°"),
        Expectation(id: "e2", rect: (20, 2273.92306, 231.96152, 60), unturned: nil,
                    why: "not Pen's first-pass 211.96"),
    ]

    @Test("Woodcase keeps the converged layout where Pen's first pass differs", arguments: converged)
    func convergedLayout(_ expected: Expectation) throws {
        try Self.check(expected, in: Self.layout())
    }

    @Test("Laying out the settled document again changes nothing")
    func idempotent() throws {
        let url = try #require(Bundle.module.url(
            forResource: "flex-turned-fill", withExtension: "pen", subdirectory: "Fixtures"
        ))
        let document = try PenParser.parse(contentsOf: url)
        let first = PenLayoutEngine.layout(document)
        let again = PenLayoutEngine.layoutIncremental(document, previousRects: first, dirtyNodeIDs: ["h3", "e1", "v1"])
        #expect(again == first)
    }
}
