//
//  SwiftUIEmitterGoldenTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Golden coverage for the SwiftUI emitter: the page file each layout fixture and
/// `render-text.pen` emits, pinned whole.
///
/// This suite needs nothing but Foundation, so it runs wherever the library builds;
/// ``SwiftUIRenderTests`` compiles and renders the same files on macOS. Regenerate with
/// `UPDATE_GOLDEN=1 swift test --filter SwiftUIEmitterGoldenTests`, then read the diff.
struct SwiftUIEmitterGoldenTests {
    @Test("Each fixture's page matches its golden", arguments: SwiftUIFixtures.names)
    func pageMatchesGolden(fixture: String) throws {
        let page = try SwiftUIFixtures.page(fixture)
        try GoldenFile.assert(page.content, name: "\(fixture).swift", subdirectory: "swiftui")
    }

    @Test("Each paint fixture's pages match its golden, all pages in one file", arguments: SwiftUIFixtures.paintFixtures)
    func paintPagesMatchGolden(fixture: String) throws {
        let pages = try SwiftUIFixtures.pages(fixture)
        #expect(pages.count > 1)
        let content = pages.map { "// MARK: \($0.path)\n\n\($0.content)" }.joined(separator: "\n")
        try GoldenFile.assert(content, name: "\(fixture).swift", subdirectory: "swiftui")
    }

    /// The themed fixtures: one axis and a context node, two axes read by a page, two
    /// bridged axes over many components, and three axes of which none is light and dark.
    static let themeFixtures = ["render-theme-axis", "parser-themed-variables", "woodcase-app", "banking"]

    @Test("Each themed fixture's theme files and pages match its golden, all in one file", arguments: themeFixtures)
    func themeMatchesGolden(fixture: String) throws {
        let files = try SwiftUIFixtures.emit(fixture).files
            .filter { $0.path.contains("/Theme/") || $0.path.contains("/Pages/") }
        #expect(files.contains { $0.path.hasSuffix("/Theme/PenTheme.swift") })
        let content = files.map { "// MARK: \($0.path)\n\n\($0.content)" }.joined(separator: "\n")
        try GoldenFile.assert(content, name: "\(fixture).swift", subdirectory: "swiftui/theme")
    }

    @Test("The fixture list covers every layout fixture and render-text")
    func fixtureListIsComplete() {
        #expect(SwiftUIFixtures.names.count == 36)
        #expect(SwiftUIFixtures.names.contains("render-text"))
        #expect(SwiftUIFixtures.rendered.count == 34)
    }
}
