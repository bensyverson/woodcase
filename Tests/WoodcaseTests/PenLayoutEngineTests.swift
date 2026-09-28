//
//  PenLayoutEngineTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-03-22.
//

import Foundation
import Testing
import Woodcase

struct PenLayoutEngineTests {
    // MARK: - Helpers

    private enum FixtureLoadError: Error {
        case notFound(String)
    }

    private func fixtureURL(_ name: String) throws -> URL {
        let nameWithoutExtension = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        guard let url = Bundle.module.url(forResource: nameWithoutExtension, withExtension: ext, subdirectory: "Fixtures") else {
            throw FixtureLoadError.notFound(name)
        }
        return url
    }

    private func loadFixture(_ name: String) throws -> (document: PenDocument, expected: [String: PenRect]) {
        let penURL = try fixtureURL("\(name).pen")
        let layoutURL = try fixtureURL("\(name).layout.json")

        let document = try PenParser.parse(contentsOf: penURL)
        let layoutData = try Data(contentsOf: layoutURL)
        let expected = try JSONDecoder().decode([String: PenRect].self, from: layoutData)

        return (document, expected)
    }

    private func assertRectsEqual(
        _ actual: [String: PenRect],
        _ expected: [String: PenRect],
        tolerance: Double = 0.5,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            actual.count == expected.count,
            "Rect count mismatch: got \(actual.count), expected \(expected.count)",
            sourceLocation: sourceLocation
        )
        for (id, expectedRect) in expected {
            guard let actualRect = actual[id] else {
                Issue.record("Missing rect for node \(id)", sourceLocation: sourceLocation)
                continue
            }
            #expect(
                abs(actualRect.x - expectedRect.x) < tolerance,
                "x mismatch for \(id): got \(actualRect.x), expected \(expectedRect.x)",
                sourceLocation: sourceLocation
            )
            #expect(
                abs(actualRect.y - expectedRect.y) < tolerance,
                "y mismatch for \(id): got \(actualRect.y), expected \(expectedRect.y)",
                sourceLocation: sourceLocation
            )
            #expect(
                abs(actualRect.width - expectedRect.width) < tolerance,
                "width mismatch for \(id): got \(actualRect.width), expected \(expectedRect.width)",
                sourceLocation: sourceLocation
            )
            #expect(
                abs(actualRect.height - expectedRect.height) < tolerance,
                "height mismatch for \(id): got \(actualRect.height), expected \(expectedRect.height)",
                sourceLocation: sourceLocation
            )
        }
    }

    // MARK: - All 26 Layout Fixtures

    static let layoutFixtures: [String] = [
        "layout-absolute",
        "layout-align-center",
        "layout-align-end",
        "layout-align-start",
        "layout-deep-nesting",
        "layout-fill-container",
        "layout-fill-container-toplevel",
        "layout-fill-fallback",
        "layout-fit-content",
        "layout-fit-content-fallback",
        "layout-gap",
        "layout-horizontal",
        "layout-justify-center",
        "layout-justify-end",
        "layout-justify-space-around",
        "layout-justify-space-between",
        "layout-justify-start",
        "layout-mixed-fill",
        "layout-multi-fill",
        "layout-nested",
        "layout-padding-2val",
        "layout-padding-4val",
        "layout-padding-uniform",
        "layout-single-child",
        "layout-vertical",
        "layout-zero-children",
    ]

    @Test("Layout matches Pencil ground truth", arguments: layoutFixtures)
    func layoutMatchesGroundTruth(_ fixtureName: String) throws {
        let (document, expected) = try loadFixture(fixtureName)
        let actual = PenLayoutEngine.layout(document)
        assertRectsEqual(actual, expected)
    }

    /// The text-in-flex boards: IBM Plex Sans text beside `fill_container` and
    /// `fit_content` siblings.
    static let textLayoutFixtures: [String] = [
        "layout-text-auto-beside-fill",
        "layout-text-auto-overflow",
        "layout-text-chips",
        "layout-text-fill-beside-fit",
        "layout-text-fixed-width-wrap",
        "layout-text-list-row",
        "layout-text-two-fill",
        "layout-text-vertical-fill",
    ]

    /// Every rect on the text boards is held to the exact tolerance since the suites measure
    /// IBM Plex Sans in Google's variable face, as Pen does, and a squeezed
    /// `fill_container` keeps Pen's 1-pt minimum (leaf BpaSrF). With the static cuts before
    /// it, 17 rects on these boards sat 1–3 pt off (`Vertical stack`, 18 pt SemiBold: 112
    /// against 114), and the boards needed a 3.5 pt tolerance
    /// (`project/2026-09-28-pen-font-faces.md`).
    @Test("Text-in-flex layout matches Pen", arguments: textLayoutFixtures)
    func textLayoutMatchesGroundTruth(_ fixtureName: String) throws {
        TestFontRegistration.registerTestFonts()
        let (document, expected) = try loadFixture(fixtureName)
        assertRectsEqual(PenLayoutEngine.layout(document), expected)
    }

    // MARK: - Edge Cases

    @Test("Empty document produces empty layout")
    func emptyDocument() {
        let doc = PenDocument(version: "0.0.1", children: [])
        let result = PenLayoutEngine.layout(doc)
        #expect(result.isEmpty)
    }

    @Test("Leaf-only document produces rects for each leaf")
    func leafOnlyDocument() {
        let doc = PenDocument(version: "0.0.1", children: [
            PenNode(
                id: "rect1",
                common: PenNodeCommon(x: .literal(10), y: .literal(20)),
                kind: .rectangle(PenNode.RectangleData(
                    width: .fixed(100),
                    height: .fixed(50)
                ))
            ),
        ])
        let result = PenLayoutEngine.layout(doc)
        #expect(result.count == 1)
        #expect(result["rect1"] == PenRect(x: 10, y: 20, width: 100, height: 50))
    }

    // MARK: - Groups

    @Test("Group children are positioned at their own explicit x/y, not flex-arranged")
    func groupChildrenPositionedAbsolutely() {
        // GroupData carries no layout properties: a group always behaves as an
        // absolute container, regardless of how many children it has.
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "group1",
                common: PenNodeCommon(),
                kind: .group(PenNode.GroupData(
                    children: [
                        PenNode(
                            id: "a",
                            common: PenNodeCommon(x: .literal(10), y: .literal(20)),
                            kind: .rectangle(PenNode.RectangleData(width: .fixed(30), height: .fixed(40)))
                        ),
                        PenNode(
                            id: "b",
                            common: PenNodeCommon(x: .literal(100), y: .literal(5)),
                            kind: .rectangle(PenNode.RectangleData(width: .fixed(20), height: .fixed(20)))
                        ),
                    ]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)

        // Each child keeps its own declared position and size — a flex layout
        // would instead stack them one after another starting at (0, 0).
        #expect(rects["a"] == PenRect(x: 10, y: 20, width: 30, height: 40))
        #expect(rects["b"] == PenRect(x: 100, y: 5, width: 20, height: 20))
    }

    // MARK: - Rotation Bounding Box

    @Test("Rotated child expands layout rect to rotated bounding box")
    func rotatedChildBoundingBox() throws {
        // An 80×80 rectangle rotated 45° has a bounding box of 80*sqrt(2) ≈ 113.137
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    layout: .horizontal,
                    gap: .literal(32),
                    padding: .uniform(.literal(48)),
                    children: [
                        PenNode(
                            id: "rotated",
                            common: PenNodeCommon(rotation: .literal(45)),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(80),
                                height: .fixed(80)
                            ))
                        ),
                        PenNode(
                            id: "normal",
                            common: PenNodeCommon(),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(80),
                                height: .fixed(80)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)

        let rotatedRect = try #require(rects["rotated"])
        let expectedBBox = 80.0 * 2.0.squareRoot() // ≈ 113.137

        // Rotated node's layout rect should be the bounding box size
        #expect(abs(rotatedRect.width - expectedBBox) < 0.5)
        #expect(abs(rotatedRect.height - expectedBBox) < 0.5)

        // Normal node should be positioned after the rotated bounding box + gap
        let normalRect = try #require(rects["normal"])
        let expectedNormalX = 48 + expectedBBox + 32 // padding + rotatedBBox + gap
        #expect(abs(normalRect.x - expectedNormalX) < 0.5)
    }

    // MARK: - Disabled Children

    @Test("Disabled children are excluded from flow layout")
    func disabledChildrenExcludedFromLayout() throws {
        // A horizontal frame with padding 8, gap 6, containing:
        // - An enabled 24×24 child
        // - A disabled 43×21 text child
        // The frame should be 40×40 (pad 8 + 24 + pad 8), not 89×40.
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    layout: .horizontal,
                    gap: .literal(6),
                    padding: .uniform(.literal(8)),
                    justifyContent: .center,
                    alignItems: .center,
                    children: [
                        PenNode(
                            id: "icon",
                            common: PenNodeCommon(),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(24),
                                height: .fixed(24)
                            ))
                        ),
                        PenNode(
                            id: "label",
                            common: PenNodeCommon(enabled: .literal(false)),
                            kind: .text(PenNode.TextData(
                                width: .fitContent(fallback: nil),
                                height: .fitContent(fallback: nil),
                                content: .literal("Button"),
                                fontFamily: .literal("Inter"),
                                fontSize: .literal(14)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)
        let frameRect = try #require(rects["frame1"])

        // With the disabled label excluded, frame width = 8 + 24 + 8 = 40
        #expect(frameRect.width == 40)
        #expect(frameRect.height == 40)

        // The disabled label should not have a layout rect (or should be zero-sized)
        let labelRect = rects["label"]
        let labelTakesSpace = labelRect.map { $0.width > 0 && $0.height > 0 } ?? false
        #expect(!labelTakesSpace, "Disabled label should not take up space in layout")
    }

    @Test("Disabled children do not contribute gap")
    func disabledChildrenNoGap() throws {
        // A frame with 3 children, middle one disabled.
        // Gap should only apply between the 2 enabled children.
        let doc = PenDocument(version: "2.9", children: [
            PenNode(
                id: "frame1",
                common: PenNodeCommon(),
                kind: .frame(PenNode.FrameData(
                    layout: .horizontal,
                    gap: .literal(10),
                    children: [
                        PenNode(
                            id: "a",
                            common: PenNodeCommon(),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(20),
                                height: .fixed(20)
                            ))
                        ),
                        PenNode(
                            id: "b",
                            common: PenNodeCommon(enabled: .literal(false)),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(20),
                                height: .fixed(20)
                            ))
                        ),
                        PenNode(
                            id: "c",
                            common: PenNodeCommon(),
                            kind: .rectangle(PenNode.RectangleData(
                                width: .fixed(20),
                                height: .fixed(20)
                            ))
                        ),
                    ]
                ))
            ),
        ])
        let rects = PenLayoutEngine.layout(doc)
        let frameRect = try #require(rects["frame1"])

        // Width = 20 + 10 + 20 = 50 (not 20 + 10 + 20 + 10 + 20 = 80)
        #expect(frameRect.width == 50)
    }
}
