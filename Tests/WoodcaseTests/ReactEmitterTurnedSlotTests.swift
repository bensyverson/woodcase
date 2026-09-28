//
//  ReactEmitterTurnedSlotTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A turned child of a flex flow takes a slot the size of its turned bounds, as Pen's
/// layout gives it, with its unturned box centred and turned inside (leaf Mu4JsL,
/// `render-transforms-and-effects`): margins grow — or, for a box turned onto its side,
/// shrink — the flex item by half the difference on each side.
struct ReactEmitterTurnedSlotTests {
    /// The emitted `Card` component: a frame laid out `layout` holding `child`, given as JSON.
    private func card(layout: String = "horizontal", child: String) throws -> String {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "\(layout)",
           "children": [\(child)]}]}
        """)
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document)
        ).files
        return try #require(files.first { $0.path == "components/Card.tsx" }).content
    }

    @Test("An 80 × 80 box turned 45° grows its slot to 113.137 on each side")
    func squareAt45() throws {
        let content = try card(child: ##"{"type": "rectangle", "id": "R1", "width": 80, "height": 80, "rotation": 45, "fill": "#FF0000"}"##)
        #expect(content.contains(##"margin: "16.569px 16.569px","##), "\(content)")
        #expect(content.contains(##"transform: "rotate(-45deg)","##), "\(content)")
        #expect(!content.contains("transformOrigin"), "\(content)")
    }

    @Test("A box turned onto its side trades its width for its height", arguments: [90.0, -90.0, 270.0])
    func quarterTurn(rotation: Double) throws {
        let content = try card(child: ##"{"type": "rectangle", "id": "R1", "width": 100, "height": 20, "rotation": \##(rotation), "fill": "#FF0000"}"##)
        #expect(content.contains(##"margin: "40px -40px","##), "\(content)")
    }

    /// Green on its first run: a guard on what the change must leave alone.
    @Test("A half turn, a flip and a turn of a node whose size CSS decides leave the slot alone", arguments: [
        ##"{"type": "rectangle", "id": "R1", "width": 100, "height": 20, "rotation": 180, "fill": "#FF0000"}"##,
        ##"{"type": "rectangle", "id": "R1", "width": 100, "height": 20, "flipX": true, "fill": "#FF0000"}"##,
        ##"{"type": "rectangle", "id": "R1", "width": "fill_container", "height": 20, "rotation": 30, "fill": "#FF0000"}"##,
        ##"{"type": "text", "id": "T1", "content": "Hi", "rotation": 30}"##,
    ])
    func slotUnchanged(child: String) throws {
        let content = try card(child: child)
        #expect(!content.contains("margin:"), "\(content)")
    }

    /// Green on its first run: a guard on what the change must leave alone.
    @Test("A free-positioned turned node keeps its anchor pivot and takes no slot")
    func freeNodeNoSlot() throws {
        let content = try card(layout: "none", child: ##"{"type": "rectangle", "id": "R1", "x": 10, "y": 10, "width": 80, "height": 80, "rotation": 45, "fill": "#FF0000"}"##)
        #expect(!content.contains("margin:"), "\(content)")
        #expect(content.contains(##"transformOrigin: "0 0""##), "\(content)")
    }

    @Test("A turned frame, a polygon and an icon in a flow grow their slots too", arguments: [
        ##"{"type": "frame", "id": "F1", "width": 80, "height": 80, "rotation": 45, "fill": "#FF0000"}"##,
        ##"{"type": "polygon", "id": "P1", "width": 80, "height": 80, "polygonCount": 5, "rotation": 45, "fill": "#FF0000"}"##,
        ##"{"type": "icon", "id": "I1", "icon": "bell", "library": "lucide", "width": 80, "height": 80, "rotation": 45, "fill": "#FF0000"}"##,
    ])
    func otherKinds(child: String) throws {
        let content = try card(child: child)
        #expect(content.contains(##"margin: "16.569px 16.569px","##), "\(content)")
    }

    // MARK: - Turned fill children (leaf ozlazY)

    /// The emitted `Card` component: a 300 × 120 frame laid out `layout`, padding 10, gap 10,
    /// holding `children` (JSON), and the warnings the emitter gave.
    private func sizedCard(layout: String = "horizontal", _ children: [String]) throws -> (content: String, warnings: [String]) {
        let document = try PenParser.parse("""
        {"version": "2.17",
         "children": [{"type": "frame", "id": "Card1", "name": "Card", "reusable": true, "layout": "\(layout)",
           "width": 300, "height": 120, "padding": 10, "gap": 10, "children": [\(children.joined(separator: ","))]}]}
        """)
        let collector = PenDiagnosticCollector()
        let files = ReactEmitter.emit(
            document: document, components: ComponentAnalyzer.analyze(document), theme: ThemeAnalyzer.analyze(document),
            diagnostics: collector
        ).files
        let content = try #require(files.first { $0.path == "components/Card.tsx" }).content
        return (content, collector.diagnostics.map(\.message))
    }

    private static let square = ##"{"type": "rectangle", "id": "A1", "width": 40, "height": 40, "fill": "#0000FF"}"##

    @Test("A turned main-axis fill takes Pen's share of the row as its width, then grows to its turned slot")
    func turnedMainFill() throws {
        let (content, warnings) = try sizedCard([
            Self.square,
            ##"{"type": "rectangle", "id": "R1", "width": "fill_container", "height": 40, "rotation": 30, "fill": "#FF0000"}"##,
        ])
        // 280 inner − 40 − 10 gap = 230; turned 30°: 219.186 × 149.641.
        #expect(content.contains("width: 230,"), "\(content)")
        #expect(!content.contains(##"width: "100%""##), "\(content)")
        #expect(content.contains(##"margin: "54.821px -5.407px","##), "\(content)")
        #expect(content.contains("flexShrink: 0,"), "\(content)")
        #expect(warnings.isEmpty, "\(warnings)")
    }

    @Test("A turned cross-axis fill takes the column's inner width as its box")
    func turnedCrossFill() throws {
        let (content, _) = try sizedCard(layout: "vertical", [
            ##"{"type": "rectangle", "id": "R1", "width": "fill_container", "height": 30, "rotation": 90, "fill": "#FF0000"}"##,
        ])
        // 280 wide, 30 tall, turned onto its side: a 30 × 280 slot.
        #expect(content.contains("width: 280,"), "\(content)")
        #expect(content.contains(##"margin: "125px -125px","##), "\(content)")
    }

    @Test("An unturned fill sharing a row with a turned one takes the same share")
    func sharingFillPinned() throws {
        let (content, _) = try sizedCard([
            ##"{"type": "rectangle", "id": "R1", "width": "fill_container", "height": 40, "rotation": 30, "fill": "#FF0000"}"##,
            ##"{"type": "rectangle", "id": "R2", "width": "fill_container", "height": 40, "fill": "#00FF00"}"##,
        ])
        // (280 − 10 gap) / 2 = 135 each.
        #expect(content.components(separatedBy: "width: 135,").count == 3, "\(content)")
    }

    @Test("A turned fill child whose share only the layout knows keeps its unturned slot, with a warning")
    func unresolvedWarns() throws {
        let (content, warnings) = try sizedCard([
            ##"{"type": "text", "id": "T1", "content": "Hi"}"##,
            ##"{"type": "rectangle", "id": "R1", "name": "Bar", "width": "fill_container", "height": 40, "rotation": 30, "fill": "#FF0000"}"##,
        ])
        #expect(content.contains(##"width: "100%""##), "\(content)")
        #expect(!content.contains("margin:"), "\(content)")
        #expect(warnings.contains { $0.contains("turned fill_container \"Bar\"") }, "\(warnings)")
    }
}
