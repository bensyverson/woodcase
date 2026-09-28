//
//  SwiftUIEmitterTurnedFillTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins how the SwiftUI emitter sizes a turned `fill_container` child of a stack: its
/// unturned box as Pen fills it, framed to its turned bounds, when the container's numbers
/// fix that box (``TurnedFillSizes``); otherwise a flexible frame and a warning (leaf ozlazY).
struct SwiftUIEmitterTurnedFillTests {
    @Test("A turned main-axis fill is framed to Pen's share, then to its turned bounds")
    func turnedMainFill() throws {
        let (code, warnings) = try body(children: [
            ##"{"type": "rectangle", "id": "a", "width": 40, "height": 40, "fill": "#0000FF"}"##,
            ##"{"type": "rectangle", "id": "b", "width": "fill_container", "height": 40, "rotation": 30, "fill": "#FF0000"}"##,
        ])
        // 380 inner − 40 − 10 gap = 330; turned 30°: 305.788 × 199.641.
        #expect(code.contains(".frame(width: 330, height: 40)"), "\(code)")
        #expect(code.contains(".frame(width: 305.788383, height: 199.641016)"), "\(code)")
        #expect(!code.contains("maxWidth: .infinity"), "\(code)")
        #expect(warnings.isEmpty, "\(warnings)")
    }

    @Test("A turned cross-axis fill is framed to the row's inner height, then to its turned bounds")
    func turnedCrossFill() throws {
        let (code, _) = try body(children: [
            ##"{"type": "rectangle", "id": "b", "width": 60, "height": "fill_container", "rotation": 90, "fill": "#FF0000"}"##,
        ])
        #expect(code.contains(".frame(width: 60, height: 280)"), "\(code)")
        #expect(code.contains(".frame(width: 280, height: 60)"), "\(code)")
    }

    @Test("An unturned fill sharing a row with a turned one is framed to the same share")
    func sharingFillPinned() throws {
        let (code, _) = try body(children: [
            ##"{"type": "rectangle", "id": "b", "width": "fill_container", "height": 40, "rotation": 30, "fill": "#FF0000"}"##,
            ##"{"type": "rectangle", "id": "d", "width": "fill_container", "height": 40, "fill": "#00FF00"}"##,
        ])
        // (380 − 10 gap) / 2 = 185 each.
        #expect(code.components(separatedBy: ".frame(width: 185, height: 40)").count == 3, "\(code)")
    }

    @Test("A turned fill whose share only the layout knows keeps a flexible frame, with a warning")
    func unresolvedWarns() throws {
        let (code, warnings) = try body(children: [
            ##"{"type": "text", "id": "t", "content": "Hi"}"##,
            ##"{"type": "rectangle", "id": "b", "name": "Bar", "width": "fill_container", "height": 40, "rotation": 30, "fill": "#FF0000"}"##,
        ])
        #expect(code.contains("maxWidth: .infinity"), "\(code)")
        #expect(warnings.contains { $0.contains("turned fill_container \"Bar\"") }, "\(warnings)")
    }

    /// The page body of a 400 × 300 row, padding 10, gap 10, holding `children` (JSON), and
    /// the warnings the emitter gave.
    private func body(children: [String]) throws -> (code: String, warnings: [String]) {
        let json = ##"{"version": "2.19", "children": [{"type": "frame", "id": "root", "name": "Board", "layout": "horizontal", "width": 400, "height": 300, "padding": 10, "gap": 10, "children": [\##(children.joined(separator: ","))]}]}"##
        let document = try PenParser.parse(Data(json.utf8))
        let collector = PenDiagnosticCollector()
        let result = try SwiftUIEmitter.emit(
            document: document, components: [], pages: PageAnalyzer.analyze(document),
            theme: ThemeAnalyzer.analyze(document), diagnostics: collector
        )
        let code = try #require(result.files.first { $0.path.hasSuffix("Pages/Board.swift") }).content
        return (code, collector.diagnostics.map(\.message))
    }
}
