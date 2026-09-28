//
//  ReactEmitterPaintGoldenTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Goldens for non-solid paints on text and strokes, from `react-paints.pen`: gradient and
/// stacked, blended text; a gradient outer stroke on a rounded rectangle (the masked
/// overlay); a gradient stroke on a path (the SVG paint server); and an image stroke with
/// per-side widths.
struct ReactEmitterPaintGoldenTests {
    private func files() throws -> [GeneratedFile] {
        // The emitter measures the fonts it names: register them, whatever ran before.
        TestFontRegistration.registerTestFonts()
        let url = try #require(
            Bundle.module.url(forResource: "react-paints", withExtension: "pen", subdirectory: "Fixtures")
        )
        let document = try PenParser.parse(contentsOf: url)
        return ReactEmitter.emit(
            document: document,
            components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document)
        ).files
    }

    @Test("Paint goldens match", arguments: ["GradientText", "RoundedRing", "PathStroke", "PerSideFrame"])
    func paintGolden(component: String) throws {
        let content = try #require(files().first { $0.path == "components/\(component).tsx" }).content
        try GoldenFile.assert(content, name: "\(component).tsx", subdirectory: "paints")
    }
}
