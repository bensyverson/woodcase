//
//  SwiftUIEmitterMiterLimitTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// A stroke's miter limit in emitted SwiftUI (leaf zRp9CO): SwiftUI miters up to 10 widths
/// and Pen up to 4 (``PenNode/strokeMiterLimit``), so `StrokeStyle(miterLimit:)` is written
/// exactly where the two would draw a corner differently.
struct SwiftUIEmitterMiterLimitTests {
    /// The page's source with every line's indentation dropped.
    private func page(child: String) throws -> String {
        let json = ##"{"version": "2.19", "children": [{"type": "frame", "id": "root", "name": "Board", "children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        )
        let content = try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
        return content.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.drop { $0 == " " } }
            .joined(separator: "\n")
    }

    /// A 25° isosceles triangle, whose apex's miter is 4.62 widths: beveled at 4, mitered at 10.
    private func triangle(_ woodcase: String = "") -> String {
        """
        {"type": "path", "id": "t", "name": "Spike", "width": 33.25, "height": 150, "stroke": "#000000",
         "strokeWidth": 4, "geometry": "M16.625 0 L33.25 150 L0 150 Z",
         "metadata": {"type": "woodcase", "woodcase": {\(woodcase)}}}
        """
    }

    @Test("A corner Pen bevels and SwiftUI would miter gets Pen's limit")
    func sharpCornerGetsPensLimit() throws {
        let code = try page(child: triangle())
        #expect(code.contains("miterLimit: 4"), "\(code)")
    }

    @Test("A limit of 10 is SwiftUI's own, and is not written")
    func swiftUIsOwnLimitIsNotWritten() throws {
        let code = try page(child: triangle(#""strokeMiterLimit": 10"#))
        #expect(!code.contains("miterLimit"), "\(code)")
    }

    @Test("Corners no limit between 4 and 10 tells apart write none: a rectangle, a blunt path")
    func bluntCornersWriteNone() throws {
        let rectangle = try page(child: ##"{"type": "rectangle", "id": "r", "width": 80, "height": 40, "stroke": "#000000", "strokeWidth": 2}"##)
        #expect(!rectangle.contains("miterLimit"), "\(rectangle)")
        let blunt = try page(child: ##"{"type": "path", "id": "p", "width": 20, "height": 20, "stroke": "#000000", "strokeWidth": 2, "geometry": "M0 0 L10 20 L20 0"}"##)
        #expect(!blunt.contains("miterLimit"), "\(blunt)")
    }

    @Test("A limit below a right angle's miter bevels a rectangle, so it is written")
    func lowLimitOnRectangle() throws {
        let code = try page(child: """
        {"type": "rectangle", "id": "r", "width": 80, "height": 40, "stroke": "#000000", "strokeWidth": 2,
         "metadata": {"type": "woodcase", "woodcase": {"strokeMiterLimit": 1}}}
        """)
        #expect(code.contains("miterLimit: 1"), "\(code)")
    }

    @Test("The miter ratios of an outline are 1 / sin(half each corner's angle)")
    func miterRatios() {
        let square = CGPath(rect: CGRect(x: 0, y: 0, width: 10, height: 10), transform: nil)
        #expect(square.miterRatios.count == 4)
        #expect(square.miterRatios.allSatisfy { abs($0 - 2.0.squareRoot()) < 1e-9 })
    }
}
