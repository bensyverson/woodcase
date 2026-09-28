//
//  PenIconFontLayoutTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

struct PenIconFontLayoutTests {
    // MARK: - Helpers

    private func loadFixture() throws -> PenDocument {
        guard let url = Bundle.module.url(forResource: "parser-icon-font", withExtension: "pen", subdirectory: "Fixtures") else {
            throw FixtureError.notFound
        }
        return try PenParser.parse(contentsOf: url)
    }

    enum FixtureError: Error {
        case notFound
    }

    // MARK: - Layout

    @Test("Lays out icon nodes with correct fixed dimensions")
    func iconFixedDimensions() throws {
        let doc = try loadFixture()
        let rects = PenLayoutEngine.layout(doc)

        // First icon: 48x48 Material Symbols Outlined
        let icon1Rect = try #require(rects["icon1"])
        #expect(icon1Rect.width == 48)
        #expect(icon1Rect.height == 48)

        // Feather bell: 24x24
        let featherRect = try #require(rects["TGJms"])
        #expect(featherRect.width == 24)
        #expect(featherRect.height == 24)

        // Non-square feather loader: 12x24
        let loaderRect = try #require(rects["EGLFk"])
        #expect(loaderRect.width == 12)
        #expect(loaderRect.height == 24)

        // Phosphor chat-dots-thin: 32x32
        let phosphorRect = try #require(rects["rcsOO"])
        #expect(phosphorRect.width == 32)
        #expect(phosphorRect.height == 32)
    }

    @Test("Icon nodes participate in parent flex layout")
    func iconInFlexLayout() throws {
        let doc = try loadFixture()
        let rects = PenLayoutEngine.layout(doc)

        // All icons should be laid out horizontally (default layout) inside the frame
        // They should have non-overlapping x positions
        let icon1 = try #require(rects["icon1"])
        let icon2 = try #require(rects["xI7eY"])
        #expect(icon2.x > icon1.x, "Second icon should be to the right of first")

        let lastIcon = try #require(rects["icon3"])
        #expect(lastIcon.x > icon2.x, "Last icon should be to the right of second")
    }
}
