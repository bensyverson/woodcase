//
//  PenTextLayoutInkTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
@testable import Woodcase

/// ``PenTextLayout/inkBounds`` is the ink ``PenLayoutEngine/textInkBounds(of:box:)``
/// reports, on every text node of the render-text fixtures — so a renderer that sizes its
/// bitmap from the layout reaches as far as the layout engine says the text paints.
struct PenTextLayoutInkTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    private static let fixtures = [
        "render-text", "render-text-fills", "render-text-line-height", "render-text-shadows",
        "render-text-unfilled", "text-line-height-rounding", "text-natural-line-height",
    ]

    @Test("Ink bounds equal textInkBounds on the render-text fixtures", arguments: fixtures)
    func inkMatches(fixture: String) throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(fixture).pen")
        let document = try PenParser.parse(Data(contentsOf: url))
        let resolved = PenVariableResolver.resolve(PenRefExpander.expand(document))
        let rects = PenLayoutEngine.layout(resolved)
        var stack = resolved.children
        var compared = 0
        while let node = stack.popLast() {
            switch node.kind {
            case let .frame(data): stack += data.children ?? []
            case let .group(data): stack += data.children ?? []
            case .text:
                guard let rect = rects[node.id] else { continue }
                let box = PenRect(x: 0, y: 0, width: rect.width, height: rect.height)
                let expected = PenLayoutEngine.textInkBounds(of: node, box: box)
                let layout = PenTextLayout(node, box: CGSize(width: rect.width, height: rect.height))
                let ink = layout?.inkBounds.map {
                    PenRect(x: Double($0.minX), y: Double($0.minY), width: Double($0.width), height: Double($0.height))
                }
                #expect(ink == expected, "\(fixture) \(node.id)")
                compared += 1
            default: break
            }
        }
        #expect(compared > 0)
    }
}
