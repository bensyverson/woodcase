//
//  PenIconFontSnapshotTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import ImageIO
import Testing
import UniformTypeIdentifiers
import Woodcase

struct PenIconFontSnapshotTests {
    private let fixturesDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fixtures")

    private let outputDir = TestOutputDirectory.url

    // MARK: - Snapshot

    @Test("Icon font test fixture renders with acceptable MAE vs Pencil")
    func iconFontSnapshotMAE() throws {
        let penURL = fixturesDir.appendingPathComponent("parser-icon-font.pen")
        let document = try PenParser.parse(contentsOf: penURL)
        let expanded = PenRefExpander.expand(document)
        let resolved = PenVariableResolver.resolve(expanded)
        let rects = PenLayoutEngine.layout(resolved)

        guard let rootRect = rects["root1"] else {
            Issue.record("No layout rect for root1")
            return
        }
        let size = CGSize(width: rootRect.width, height: rootRect.height)

        guard let image = PenRenderer.render(
            resolved,
            layoutRects: rects,
            size: size,
            scale: 2,
            rootNodeID: "root1"
        ) else {
            Issue.record("Render failed")
            return
        }

        // Save for visual inspection
        try FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)
        let outputURL = outputDir.appendingPathComponent("icon-font-test.png")
        guard let dest = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            Issue.record("Failed to create image destination")
            return
        }
        CGImageDestinationAddImage(dest, image, nil)
        guard CGImageDestinationFinalize(dest) else {
            Issue.record("Failed to save PNG")
            return
        }
        print("Saved: \(outputURL.path)")

        // Compare against Pencil reference
        guard let reference = PenSnapshotTestHelpers.loadFixtureImage(
            named: "icon-font-test", fixturesDir: fixturesDir
        ) else {
            Issue.record("Missing Pencil reference: icon-font-test.png")
            return
        }

        let mae = PenSnapshotTestHelpers.meanAbsoluteError(between: image, and: reference)
        print("  icon-font-test MAE vs Pencil: \(String(format: "%.2f", mae))")
        // max(measured×1.5, measured+0.25); measured 0.89 (swift test -j 3 --filter PenIconFontSnapshotTests,
        // 2026-09-27, leaf 6vLFNQ). 1.24 while Core Text moved Material Symbols' `opsz` axis to the point size
        // (leaf VMKixs); 5.25 while glyphs were centred by their ink rather than placed by the font's metrics.
        #expect(mae < 1.34, "Icon font MAE \(String(format: "%.2f", mae)) exceeds threshold")
    }
}
