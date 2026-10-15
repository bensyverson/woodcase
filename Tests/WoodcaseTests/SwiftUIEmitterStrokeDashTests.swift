//
//  SwiftUIEmitterStrokeDashTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A dashed stroke in emitted SwiftUI: `StrokeStyle(dash:dashPhase:)` beside the width,
/// cap and join.
struct SwiftUIEmitterStrokeDashTests {
    private static let dashed = #""metadata": {"type": "woodcase", "woodcase": {"strokeDash": [8, 4], "strokeDashOffset": 3}}"#

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

    @Test("A dashed centered stroke names its dash and phase in its StrokeStyle",
          arguments: [
              #""type": "rectangle", "width": 80, "height": 40, "cornerRadius": 8"#,
              #""type": "ellipse", "width": 80, "height": 40"#,
              #""type": "path", "width": 80, "height": 40, "geometry": "M0 0 L80 0 L80 40""#,
          ])
    func centered(keys: String) throws {
        let code = try page(child: """
        {\(keys), "id": "s", "name": "Shape", "stroke": "#FF0000", "strokeWidth": 2, "strokeLinecap": "round", \(Self.dashed)}
        """)
        #expect(code.contains("StrokeStyle(lineWidth: 2, lineCap: .round, dash: [8, 4], dashPhase: 3)"), "\(code)")
    }

    @Test("A dashed inner stroke dashes the band it is drawn as")
    func inner() throws {
        let code = try page(child: """
        {"type": "rectangle", "width": 80, "height": 40, "id": "s", "name": "Shape", "stroke": "#FF0000",
         "strokeWidth": 2, "strokeAlignment": "inner", \(Self.dashed)}
        """)
        #expect(code.contains("dash: [8, 4], dashPhase: 3"), "\(code)")
    }
}
