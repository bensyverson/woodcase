//
//  ReactEmitterPathBoundsTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A `path` without a `viewBox`, in emitted React.
///
/// Pen maps a path's tight bounds onto its box, stretching each axis on its own
/// (``PenPath/sourceRegion(viewBox:)``), so geometry drawn smaller or larger than the box
/// fills it (`render-fill-domains.pen`'s `evenodd-h` and `curve-v`). React writes those
/// bounds as the SVG's `viewBox`, with `preserveAspectRatio="none"`, as it writes a
/// declared one.
struct ReactEmitterPathBoundsTests {
    /// The emitted `Card` component holding a 200×120 path of `geometry`.
    private func card(geometry: String, width: Int = 200, height: Int = 120) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [{"type": "path", "id": "Pth01", "name": "Shape", "width": \(width), "height": \(height),
             "geometry": "\(geometry)", "fill": "#FF0000"}]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    @Test("A path smaller than its box is stretched from its tight bounds; one that fills it is drawn as written")
    func stretched() throws {
        let content = try card(geometry: "M0 100 C0 0 100 0 100 100 Z")
        #expect(content.contains(##"viewBox="0 25 100 75" preserveAspectRatio="none" overflow="visible""##), "\(content)")

        let fitted = try card(geometry: "M0 0 L40 0 L40 40 Z", width: 40, height: 40)
        #expect(fitted.contains(##"viewBox="0 0 40 40""##), "\(fitted)")
        #expect(!fitted.contains("preserveAspectRatio"), "\(fitted)")
    }
}
