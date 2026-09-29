//
//  SwiftUIEmitterUnfilledPaintTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// What a text or icon with no enabled fill becomes: nothing visible, as Pen draws it
/// (`pen` export of `swiftui-color-scheme.pen`, 2026-09-27), whatever the color scheme.
/// Left unstyled, SwiftUI would draw the text in `.primary` — black in light, white in
/// dark. ``SwiftUIRenderTests`` renders the fixture's `unfilled` board in both schemes.
struct SwiftUIEmitterUnfilledPaintTests {
    @Test("A text with no fill is clear, before its growth frame")
    func unfilledText() throws {
        let code = try body(##"{"type": "text", "id": "t", "content": "Hi"}"##)
        #expect(code.contains(".foregroundStyle(.clear)\n                .fixedSize()\n"))
    }

    @Test("A text whose every fill is disabled is clear")
    func disabledFills() throws {
        let text = ##"{"type": "text", "id": "t", "content": "Hi", "fill": [{"type": "color", "color": "#FF0000", "enabled": false}]}"##
        let code = try body(text)
        #expect(code.contains(".foregroundStyle(.clear)"))
    }

    @Test("A text with an empty fill list is clear")
    func emptyFills() throws {
        let code = try body(##"{"type": "text", "id": "t", "content": "Hi", "fill": []}"##)
        #expect(code.contains(".foregroundStyle(.clear)"))
    }

    @Test("A text whose fill cannot be written is left to SwiftUI, with a warning, not hidden")
    func unwritableFill() throws {
        let diagnostics = PenDiagnosticCollector()
        let code = try body(##"{"type": "text", "id": "t", "content": "Hi", "fill": "$missing"}"##, diagnostics: diagnostics)
        #expect(!code.contains(".foregroundStyle(.clear)"))
        #expect(diagnostics.diagnostics.contains { $0.nodeID == "t" && $0.message.contains("$missing") })
    }

    @Test("An icon with no fill draws nothing")
    func unfilledIcon() throws {
        let code = try body(##"{"type": "icon", "id": "i", "icon": "square", "library": "lucide", "width": 24, "height": 24}"##)
        #expect(!code.contains("PenIconShape("))
        #expect(code.contains("Color.clear"))
    }

    // MARK: - Helpers

    private func body(_ child: String, diagnostics: PenDiagnosticCollector? = nil) throws -> String {
        let json = ##"{"version": "2.17", "children": [{"type": "frame", "id": "root", "name": "Board", "children": [\##(child)]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: diagnostics
        )
        return try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
    }
}
