//
//  PenTextMeasureRequestTests.swift
//  WoodcaseTests
//

import Foundation
import Synchronization
import Testing
import Woodcase

/// The one value a ``TextMeasurer`` is handed: what the layout engine asks it, and that the
/// default measurer answers it as ``PenTextMeasurer`` does. Imported without `@testable`, so
/// a consumer's own measurer can be written against it.
struct PenTextMeasureRequestTests {
    init() {
        TestFontRegistration.registerTestFonts()
    }

    /// Keeps every request a measurer is handed.
    private final class Recorder: Sendable {
        private let requests = Mutex<[PenTextMeasureRequest]>([])

        var all: [PenTextMeasureRequest] {
            requests.withLock { $0 }
        }

        var measurer: TextMeasurer {
            { [self] request in
                requests.withLock { $0.append(request) }
                return (10, 10)
            }
        }
    }

    private static let runs = [PenTextRun(start: 0, end: 4, fontWeight: 700)]

    private static func layout(_ data: PenNode.TextData, with measurer: TextMeasurer) {
        let node = PenNode(id: "t", common: PenNodeCommon(), kind: .text(data))
        _ = PenLayoutEngine.layout(PenDocument(version: "2.20", children: [node]), textMeasurer: measurer)
    }

    @Test("The layout engine asks with the node's style, its applied runs and its width")
    func layoutAsksWithEverything() throws {
        let recorder = Recorder()
        Self.layout(PenNode.TextData(
            width: .fixed(120), content: .literal("Bold text"), textGrowth: .fixedWidth,
            fontFamily: .literal("Inter"), fontSize: .literal(14), fontWeight: .literal("500"),
            fontStyle: .literal("italic"), letterSpacing: .literal(0.5), lineHeight: .literal(1.25),
            spans: PenTextSpans(text: "Bold text", runs: Self.runs)
        ), with: recorder.measurer)
        let request = try #require(recorder.all.first)
        #expect(request == PenTextMeasureRequest(
            text: "Bold text", fontFamily: "Inter", fontSize: 14, fontWeight: "500", fontStyle: "italic",
            letterSpacing: 0.5, lineHeight: 1.25, maxWidth: 120, runs: Self.runs
        ))
    }

    @Test("An empty text asks for one plain line, unwrapped")
    func emptyTextAsksForOneLine() throws {
        let recorder = Recorder()
        Self.layout(PenNode.TextData(content: .literal(""), fontSize: .literal(20)), with: recorder.measurer)
        let request = try #require(recorder.all.first)
        #expect(request == PenTextMeasureRequest(text: " ", fontSize: 20))
    }

    @Test("The default measurer answers a request as PenTextMeasurer measures it")
    func defaultMeasurerMatches() {
        let request = PenTextMeasureRequest(
            text: "Bold text that wraps", fontFamily: "Inter", fontSize: 14, lineHeight: 1.25,
            maxWidth: 60, runs: Self.runs
        )
        let answer = PenLayoutEngine.defaultTextMeasurer(request)
        let measured = PenTextMeasurer.measure(
            "Bold text that wraps", fontFamily: "Inter", fontSize: 14, lineHeight: 1.25, maxWidth: 60, runs: Self.runs
        )
        #expect(answer.width == Double(measured.width))
        #expect(answer.height == Double(measured.height))
    }
}
