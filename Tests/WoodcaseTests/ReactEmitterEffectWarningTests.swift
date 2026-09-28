//
//  ReactEmitterEffectWarningTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The inner shadows CSS cannot write — on text, whose glyphs have no inset shadow, and on
/// a group, which has no box — are left out, as Ben ruled on 2026-09-27, and each is
/// named by one generate-time warning per node (leaf Mu4JsL).
struct ReactEmitterEffectWarningTests {
    private static let inner = ##"{"type": "shadow", "shadowType": "inner", "color": "#000000", "offset": {"x": 2, "y": 2}, "blur": 4}"##
    private static let outer = ##"{"type": "shadow", "shadowType": "outer", "color": "#000000", "offset": {"x": 2, "y": 2}, "blur": 4}"##

    /// The React warnings about inner shadows for a `Card` component whose children are `children`.
    private func warnings(_ children: [String]) throws -> [PenDiagnostic] {
        let document = try PenParser.parse("""
        {"version": "2.19",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(children.joined(separator: ", "))]}]}
        """)
        let collector = PenDiagnosticCollector()
        _ = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: collector
        )
        return collector.diagnostics.filter { $0.message.contains("inner shadow") }
    }

    private func text(_ id: String, effect: String) -> String {
        ##"{"type": "text", "id": "\##(id)", "content": "Hi", "fill": "#000000", "effect": \##(effect)}"##
    }

    private func group(_ id: String, effect: String) -> String {
        ##"{"type": "group", "id": "\##(id)", "effect": \##(effect), "children": [{"type": "rectangle", "id": "\##(id)r", "width": 10, "height": 10, "fill": "#FF0000"}]}"##
    }

    @Test("A text's inner shadow is one warning naming the node")
    func textInnerShadow() throws {
        let found = try warnings([text("Txt01", effect: Self.inner)])
        #expect(found.map(\.nodeID) == ["Txt01"], "\(found)")
        #expect(found.first?.message == ReactEmitter.textInnerShadowWarning)
        #expect(found.first?.severity == .warning)
    }

    @Test("A group's inner shadow is one warning naming the node")
    func groupInnerShadow() throws {
        let found = try warnings([group("Grp01", effect: Self.inner)])
        #expect(found.map(\.nodeID) == ["Grp01"], "\(found)")
        #expect(found.first?.message == ReactEmitter.groupInnerShadowWarning)
    }

    @Test("Two inner shadows on one node are one warning")
    func twoShadowsOneWarning() throws {
        let found = try warnings([text("Txt01", effect: "[\(Self.inner), \(Self.inner)]")])
        #expect(found.count == 1, "\(found)")
    }

    /// Green on its first run: a guard on what the change must leave alone.
    @Test("An outer shadow, a disabled inner one, or an inner one on a box is no warning", arguments: [
        ##"{"type": "text", "id": "Txt01", "content": "Hi", "effect": \##(outer)}"##,
        ##"{"type": "text", "id": "Txt01", "content": "Hi", "effect": {"type": "shadow", "shadowType": "inner", "enabled": false}}"##,
        ##"{"type": "rectangle", "id": "Rec01", "width": 10, "height": 10, "effect": \##(inner)}"##,
    ])
    func noWarning(child: String) throws {
        #expect(try warnings([child]).isEmpty)
    }

    /// Green on its first run: it pins the ruling's other half, which the warning must keep.
    @Test("The text is still written, without the inner shadow")
    func textStillWritten() throws {
        let document = try PenParser.parse("""
        {"version": "2.19",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "vertical",
           "children": [\(text("Txt01", effect: Self.inner))]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        let content = try #require(files.first { $0.path == "components/Card.tsx" }).content
        #expect(content.contains("Hi"), "\(content)")
        #expect(!content.contains("inset"), "\(content)")
    }
}
