//
//  PenTextGeometryTests.swift
//  WoodcaseTests
//

import CoreGraphics
import Foundation
import Testing
import Woodcase

/// An editor's caret, hit-test and selection, read from ``PenTextLayout/geometry`` on the
/// shared ``PenTextLayoutSample`` fixture — imported without `@testable`, as Penumbra reads it.
@Suite(.serialized)
struct PenTextGeometryTests {
    static func layout(_ sample: PenTextLayoutSample) -> PenTextLayout {
        PenTextLayout(
            text: sample.text, style: sample.style, box: CGSize(width: sample.box.width, height: sample.box.height)
        )
    }

    static func boundaries(of text: String) -> [Int] {
        var offset = 0
        var result = [0]
        for character in text {
            offset += character.utf16.count
            result.append(offset)
        }
        return result
    }

    static func midPoint(_ rect: PenRect) -> PenPoint {
        PenPoint(x: rect.x + rect.width / 2, y: rect.y + rect.height / 2)
    }

    @Test("The multi-line sample wraps, breaks hard, and ends on an empty line", arguments: PenTextLayoutSample.multiLine)
    func sampleCoversTheCases(sample: PenTextLayoutSample) throws {
        let geometry = Self.layout(sample).geometry
        #expect(geometry.lines.contains { $0.ending == .softWrap })
        #expect(geometry.lines.contains { $0.ending == .hardBreak })
        let last = try #require(geometry.lines.last)
        #expect(last.stringRange == geometry.length ..< geometry.length)
        #expect(geometry.length == sample.text.utf16.count)
    }

    @Test("A caret's midpoint hits back to its own index, for every grapheme index and affinity",
          arguments: PenTextLayoutSample.multiLine)
    func caretRoundTrip(sample: PenTextLayoutSample) {
        let geometry = Self.layout(sample).geometry
        for index in Self.boundaries(of: sample.text) {
            let lineUp = geometry.lineIndex(containing: index, affinity: .upstream)
            let lineDown = geometry.lineIndex(containing: index, affinity: .downstream)
            for affinity in PenTextGeometry.Affinity.allCases {
                let rect = geometry.caretRect(at: index, affinity: affinity)
                #expect(rect.height == geometry.lines[0].band.height)
                let hit = geometry.index(at: Self.midPoint(rect))
                #expect(hit.index == index, "\(sample.name) \(index) \(affinity)")
                if lineUp != lineDown {
                    #expect(hit.affinity == affinity, "\(sample.name) \(index) at a soft wrap")
                }
            }
        }
    }

    @Test("A soft wrap's index is the end of one line upstream and the start of the next downstream",
          arguments: PenTextLayoutSample.multiLine)
    func softWrapAffinity(sample: PenTextLayoutSample) throws {
        let geometry = Self.layout(sample).geometry
        let wrapped = try #require(geometry.lines.firstIndex { $0.ending == .softWrap })
        let index = geometry.lines[wrapped].stringRange.upperBound
        #expect(geometry.lineIndex(containing: index, affinity: .upstream) == wrapped)
        #expect(geometry.lineIndex(containing: index, affinity: .downstream) == wrapped + 1)
        #expect(geometry.lineRange(at: index, affinity: .upstream) == geometry.lines[wrapped].stringRange)
        #expect(geometry.caretRect(at: index, affinity: .upstream).y == geometry.lines[wrapped].band.y)
        #expect(geometry.caretRect(at: index, affinity: .downstream).y == geometry.lines[wrapped + 1].band.y)
    }

    @Test("Selecting everything covers each line band from its start to its end, with no overlap between lines",
          arguments: PenTextLayoutSample.multiLine)
    func selectAll(sample: PenTextLayoutSample) throws {
        let geometry = Self.layout(sample).geometry
        let rects = geometry.selectionRects(for: 0 ..< geometry.length)
        for line in geometry.lines where !line.stringRange.isEmpty {
            let onBand = rects.filter { $0.y == line.band.y && $0.height == line.band.height }
            let minX = try #require(onBand.map(\.x).min())
            let maxX = try #require(onBand.map { $0.x + $0.width }.max())
            let first = try #require(line.carets.first), last = try #require(line.carets.last)
            #expect(minX <= min(first.x, last.x) + 1e-9, "\(sample.name) line \(line.stringRange)")
            let end = line.ending == .hardBreak ? max(geometry.box.width, last.x) : last.x
            #expect(maxX >= end - 1e-9, "\(sample.name) line \(line.stringRange)")
        }
        for (i, a) in rects.enumerated() {
            for b in rects[(i + 1)...] where a.y != b.y {
                let overlap = min(a.y + a.height, b.y + b.height) - max(a.y, b.y)
                #expect(overlap <= 1e-9, "\(sample.name) bands overlap")
            }
        }
    }

    @Test("A selection within one line spans its two carets")
    func selectionWithinLine() throws {
        let geometry = Self.layout(PenTextLayoutSample.multiLine[0]).geometry
        let rects = geometry.selectionRects(for: 4 ..< 8)
        #expect(rects.count == 1)
        let rect = try #require(rects.first)
        #expect(rect.x == geometry.caretRect(at: 4).x)
        #expect(rect.x + rect.width == geometry.caretRect(at: 8).x)
        #expect(rect.y == geometry.lines[0].band.y)
        #expect(geometry.selectionRects(for: 5 ..< 5).isEmpty)
    }

    @Test("A selection that runs past a soft wrap reaches the box's right edge on the wrapped line",
          arguments: PenTextLayoutSample.multiLine)
    func selectionAcrossSoftWrap(sample: PenTextLayoutSample) throws {
        let geometry = Self.layout(sample).geometry
        let wrapped = try #require(geometry.lines.firstIndex { $0.ending == .softWrap })
        let line = geometry.lines[wrapped]
        let next = geometry.lines[wrapped + 1]
        let start = line.stringRange.lowerBound
        let past = try #require(Self.boundaries(of: sample.text).first { $0 > next.stringRange.lowerBound })
        let rects = geometry.selectionRects(for: start ..< past)
        let onLine = try #require(rects.first { $0.y == line.band.y })
        let lastCaret = try #require(line.carets.map(\.x).max())
        // A trailing space can hang past the edge (right-aligned, justified); the rect covers it.
        #expect(onLine.x + onLine.width == max(geometry.box.width, lastCaret), "\(sample.name)")
    }

    @Test("A selection that ends at a soft wrap stops at the wrapped line's last caret",
          arguments: PenTextLayoutSample.multiLine)
    func selectionEndingAtSoftWrap(sample: PenTextLayoutSample) throws {
        let geometry = Self.layout(sample).geometry
        let wrapped = try #require(geometry.lines.firstIndex { $0.ending == .softWrap })
        let line = geometry.lines[wrapped]
        let rects = geometry.selectionRects(for: line.stringRange)
        #expect(rects.count == 1)
        let rect = try #require(rects.first)
        let carets = line.carets.map(\.x)
        #expect(rect.x + rect.width == carets.max(), "\(sample.name)")
    }

    @Test("Empty text has one caret line at Pen's first baseline, placed as a one-line block")
    func emptyText() {
        let sample = PenTextLayoutSample.empty
        let layout = Self.layout(sample)
        let geometry = layout.geometry
        #expect(geometry.lines.count == 1)
        let pitch = Double(layout.lines.pitch)
        let top = (sample.box.height - pitch.rounded(.up)) / 2
        #expect(geometry.lines[0].baseline == top + Double(layout.styled.firstBaseline))
        let caret = geometry.caretRect(at: 0)
        #expect(caret == PenRect(x: sample.box.width / 2, y: top, width: 0, height: pitch))
        #expect(geometry.index(at: PenPoint(x: 3, y: 3)) == PenTextGeometry.Position(index: 0))
    }

    @Test("Top-aligned empty text puts its caret's baseline at Pen's first baseline")
    func emptyTopAligned() {
        let layout = PenTextLayout(text: "", style: PenTextStyle(), box: CGSize(width: 100, height: 50))
        let line = layout.geometry.lines[0]
        #expect(line.baseline == Double(layout.styled.firstBaseline))
        #expect(layout.geometry.caretRect(at: 0) == PenRect(x: 0, y: 0, width: 0, height: Double(layout.lines.pitch)))
    }

    @Test("A trailing newline gets a caret line one pitch below the last, at its baseline")
    func trailingNewline() throws {
        let layout = PenTextLayout(text: "ab\n", style: PenTextStyle(), box: CGSize(width: 100, height: 50))
        let geometry = layout.geometry
        #expect(geometry.lines.count == 2)
        let pitch = Double(layout.lines.pitch)
        let line = try #require(geometry.lines.last)
        #expect(line.stringRange == 3 ..< 3)
        #expect(line.baseline == Double(layout.styled.firstBaseline) + pitch)
        #expect(geometry.caretRect(at: 3) == PenRect(x: 0, y: pitch, width: 0, height: pitch))
        #expect(geometry.caretRect(at: 2).y == 0)
    }

    @Test("Surrogate pairs and an emoji ZWJ sequence never yield a mid-cluster index",
          arguments: PenTextLayoutSample.multiLine)
    func clusters(sample: PenTextLayoutSample) {
        let geometry = Self.layout(sample).geometry
        let boundaries = Set(Self.boundaries(of: sample.text))
        for line in geometry.lines {
            var hits: Set<Int> = []
            var x = -10.0
            while x <= geometry.box.width + 10 {
                let hit = geometry.index(at: PenPoint(x: x, y: line.band.y + line.band.height / 2))
                #expect(boundaries.contains(hit.index), "\(sample.name) x \(x) → \(hit.index)")
                hits.insert(hit.index)
                x += 0.5
            }
            // Sweeping the band reaches every caret on the line, and nothing else.
            #expect(hits == Set(line.carets.map(\.index)), "\(sample.name) line \(line.stringRange)")
        }
        for index in 0 ... geometry.length where !boundaries.contains(index) {
            let snapped = boundaries.filter { $0 < index }.max() ?? 0
            #expect(geometry.caretRect(at: index) == geometry.caretRect(at: snapped), "\(sample.name) \(index)")
        }
    }

    @Test("A point above the text hits its first line, below it its last, past an end that line's end")
    func clampedHits() {
        let geometry = Self.layout(PenTextLayoutSample.multiLine[0]).geometry
        #expect(geometry.index(at: PenPoint(x: -50, y: -500)).index == 0)
        #expect(geometry.index(at: PenPoint(x: 500, y: 5000)).index == geometry.length)
        let first = geometry.lines[0]
        let hit = geometry.index(at: PenPoint(x: 1000, y: first.band.y + 1))
        #expect(hit == PenTextGeometry.Position(index: first.stringRange.upperBound, affinity: .upstream))
    }

    @Test("Up and down keep x: the nearest caret on another line")
    func verticalMotion() throws {
        let geometry = Self.layout(PenTextLayoutSample.multiLine[0]).geometry
        let x = geometry.caretRect(at: 5).x
        let below = geometry.position(onLine: 1, nearestX: x)
        let carets = geometry.caretOffsets(onLine: 1)
        #expect(carets == geometry.lines[1].carets)
        let nearest = try #require(carets.min { abs($0.x - x) < abs($1.x - x) })
        #expect(below.index == nearest.index)
    }

    @Test("The geometry round-trips through JSON")
    func codable() throws {
        let geometry = Self.layout(PenTextLayoutSample.multiLine[1]).geometry
        let data = try JSONEncoder().encode(geometry)
        #expect(try JSONDecoder().decode(PenTextGeometry.self, from: data) == geometry)
    }
}
