//
//  MeasurementCacheFinalityTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A measurement-cache hit may skip a subtree only where the subtree's rects already in
/// the map are the ones its final layout wrote.
///
/// A flex container sizes a child that fills the cross axis twice: once to measure it,
/// then at its resolved cross size. The measuring pass used to write the child's
/// descendants into the scratch map, which is merged into the target before the child is
/// laid out again — so when that second call hit the cache, the descendants kept the
/// measuring pass's rects. Here the measured text is unwrapped and the final one wraps.
@MainActor
struct MeasurementCacheFinalityTests {
    /// `P` hugs its widest child; `C` fills `P`'s width and holds a text that wraps there.
    private static func document(gap: Double) throws -> PenDocument {
        try PenParser.parse("""
        {
          "version": "2.17",
          "children": [
            { "id": "P", "type": "frame", "layout": "vertical", "gap": \(gap),
              "width": "fit_content", "height": "fit_content",
              "children": [
                { "id": "W", "type": "text", "content": "WWWWWWWWWWWWWWWWWWWW" },
                { "id": "C", "type": "frame", "layout": "vertical",
                  "width": "fill_container", "height": "fit_content",
                  "children": [
                    { "id": "T", "type": "text", "width": "fill_container",
                      "content": "A text that wraps inside the column" }
                  ] }
              ] }
          ]
        }
        """)
    }

    @Test("A cross-axis fill hit in the arrange pass keeps its final descendants' rects")
    func crossFillHitAfterMeasuring() throws {
        let measurer = RecordingTextMeasurer().measurer
        let before = try Self.document(gap: 0)
        var cache: [String: PenLayoutEngine.MeasurementCacheEntry] = [:]
        let primed = PenLayoutEngine.layoutIncremental(
            before, previousRects: PenLayoutEngine.layout(before, textMeasurer: measurer),
            dirtyNodeIDs: ["P"], textMeasurer: measurer, measurementCache: &cache
        )

        let after = try Self.document(gap: 10)
        cache.removeValue(forKey: "P")
        let incremental = PenLayoutEngine.layoutIncremental(
            after, previousRects: primed, dirtyNodeIDs: ["P"], textMeasurer: measurer, measurementCache: &cache
        )
        let full = PenLayoutEngine.layout(after, textMeasurer: measurer)
        #expect(LayoutOracle.differences(incremental, full).isEmpty, "\(LayoutOracle.differences(incremental, full))")
    }
}
