//
//  PenTextBuilderSourceTests.swift
//  WoodcaseTests
//

import Foundation
import Testing

/// Holds the text path to one attributed-string builder
/// (`PenTextStyle.attributedString(_:for:)`): the CG renderer, ink measurement and
/// `PenTextMeasurer.measure` all build through it, so a second
/// `CFAttributedStringCreate` in the library is a second builder that can drift.
@Suite("One text attributed-string builder")
struct PenTextBuilderSourceTests {
    /// The library's sources that may create an attributed string, relative to
    /// `Sources/Woodcase`: the one text builder, and three that set a single glyph or a
    /// fixed label rather than a text node — icon glyphs and the browser placeholder.
    private static let allowed: Set<String> = [
        "Rendering/PenTextStyle+AttributedString.swift",
        "Rendering/PenIconFontRenderer.swift",
        "PenLayoutEngine+IconInk.swift",
        "Rendering/PenBrowserPlaceholder.swift",
    ]

    /// `Sources/Woodcase`, found from this file's own path.
    private static var sourcesDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources/Woodcase")
    }

    @Test("Only the text builder and the non-text exceptions create attributed strings")
    func oneBuilder() throws {
        let root = Self.sourcesDirectory
        let enumerator = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var creators: Set<String> = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let source = try String(contentsOf: url, encoding: .utf8)
            if source.contains("CFAttributedStringCreate") {
                creators.insert(String(url.path.dropFirst(root.path.count + 1)))
            }
        }
        #expect(creators == Self.allowed)
    }
}
