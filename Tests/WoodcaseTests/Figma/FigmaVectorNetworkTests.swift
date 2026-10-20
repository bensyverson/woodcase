//
//  FigmaVectorNetworkTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `FigmaVectorNetwork(blob:)` reads the header, vertices, segments and regions of a
/// `vectorNetworkBlob`, and refuses a blob that does not fit its own counts.
struct FigmaVectorNetworkTests {
    private typealias Bytes = FigmaBlobBytes

    /// A closed triangle with one nonzero region, as V1a's blob is laid out.
    private static let triangle = Bytes.network(
        vertices: [(1, 0, 80), (1, 40, 0), (1, 80, 80)],
        segments: [Bytes.line(0, 1), Bytes.line(1, 2), Bytes.line(2, 0)],
        regions: [(1, [[0, 1, 2]])]
    )

    @Test("The header's counts give the vertices, segments and regions")
    func headerCounts() throws {
        let network = try FigmaVectorNetwork(blob: Self.triangle)
        #expect(network.vertices.count == 3)
        #expect(network.segments.count == 3)
        #expect(network.regions.count == 1)
    }

    @Test("A vertex is a style id and a position")
    func vertexFields() throws {
        let blob = Bytes.network(vertices: [(7, 1.5, -2.25), (0, 1e6, 0)], segments: [])
        let network = try FigmaVectorNetwork(blob: blob)
        #expect(network.vertices == [
            .init(styleID: 7, position: FigmaPoint(x: 1.5, y: -2.25)),
            .init(styleID: 0, position: FigmaPoint(x: 1e6, y: 0)),
        ])
    }

    @Test("A segment is a style id, two vertex indices and a tangent at each end")
    func segmentFields() throws {
        let blob = Bytes.network(
            vertices: [(0, 0, 0), (0, 10, 0)],
            segments: [(9, 1, 27.614_237, -0.5, 0, -13.807_119, 3)]
        )
        let segment = try #require(FigmaVectorNetwork(blob: blob).segments.first)
        #expect(segment.styleID == 9)
        #expect(segment.start == 1)
        #expect(segment.end == 0)
        #expect(segment.tangentStart == FigmaPoint(x: Double(Float(27.614_237)), y: -0.5))
        #expect(segment.tangentEnd == FigmaPoint(x: Double(Float(-13.807_119)), y: 3))
        #expect(!segment.isStraight)
        #expect(FigmaVectorNetwork.Segment(styleID: 0, start: 0, tangentStart: .zero, end: 1, tangentEnd: .zero).isStraight)
    }

    @Test("A region word packs the style id above the winding bit", arguments: [
        (UInt32(1), UInt32(0), FigmaWindingRule.nonzero),
        (0, 0, .evenOdd),
        (5, 2, .nonzero),
        (4, 2, .evenOdd),
        (UInt32.max, UInt32.max >> 1, .nonzero),
    ])
    func regionWord(word: UInt32, styleID: UInt32, rule: FigmaWindingRule) throws {
        let blob = Bytes.network(
            vertices: [(0, 0, 0), (0, 1, 0), (0, 0, 1)],
            segments: [Bytes.line(0, 1), Bytes.line(1, 2), Bytes.line(2, 0)],
            regions: [(word, [[0, 1, 2]])]
        )
        let region = try #require(FigmaVectorNetwork(blob: blob).regions.first)
        #expect(region.styleID == styleID)
        #expect(region.windingRule == rule)
    }

    @Test("A region with a hole has two loops, and a network can hold several regions")
    func loopsAndRegions() throws {
        let blob = Bytes.network(
            vertices: [(0, 0, 0), (0, 4, 0), (0, 4, 4), (0, 1, 1), (0, 2, 1), (0, 2, 2), (0, 9, 9), (0, 9, 8)],
            segments: [
                Bytes.line(0, 1), Bytes.line(1, 2), Bytes.line(2, 0),
                Bytes.line(3, 4), Bytes.line(4, 5), Bytes.line(5, 3),
                Bytes.line(6, 7),
            ],
            regions: [(0, [[0, 1, 2], [3, 4, 5]]), (3, [[6]])]
        )
        let network = try FigmaVectorNetwork(blob: blob)
        #expect(network.regions == [
            .init(styleID: 0, windingRule: .evenOdd, loops: [[0, 1, 2], [3, 4, 5]]),
            .init(styleID: 1, windingRule: .nonzero, loops: [[6]]),
        ])
    }

    @Test("An empty network decodes to nothing")
    func empty() throws {
        let network = try FigmaVectorNetwork(blob: Bytes.network(vertices: [], segments: []))
        #expect(network == FigmaVectorNetwork())
    }

    @Test("Every truncation of a blob is refused, never read past")
    func truncations() throws {
        for length in 0 ..< Self.triangle.count {
            #expect(throws: FigmaBlobError.self) {
                try FigmaVectorNetwork(blob: Self.triangle.prefix(length))
            }
        }
    }

    @Test("A count larger than the bytes that follow is refused before anything is read")
    func hugeCount() throws {
        var bytes = Bytes()
        bytes.u32(.max)
        bytes.u32(0)
        bytes.u32(0)
        #expect(throws: FigmaBlobError.countExceedsRemainingBytes(count: .max, offset: 0)) {
            try FigmaVectorNetwork(blob: bytes.data)
        }
    }

    @Test("A segment naming a vertex past the end is refused")
    func badVertexIndex() throws {
        let blob = Bytes.network(vertices: [(0, 0, 0), (0, 1, 1)], segments: [Bytes.line(0, 2)])
        #expect(throws: FigmaBlobError.vertexIndexOutOfRange(segment: 0, vertex: 2)) {
            try FigmaVectorNetwork(blob: blob)
        }
    }

    @Test("A loop naming a segment past the end is refused")
    func badSegmentIndex() throws {
        let blob = Bytes.network(vertices: [(0, 0, 0), (0, 1, 1)], segments: [Bytes.line(0, 1)], regions: [(1, [[0, 1]])])
        #expect(throws: FigmaBlobError.segmentIndexOutOfRange(region: 0, segment: 1)) {
            try FigmaVectorNetwork(blob: blob)
        }
    }

    @Test("Bytes after the last region are refused")
    func trailingBytes() throws {
        #expect(throws: FigmaBlobError.trailingBytes(offset: Self.triangle.count)) {
            try FigmaVectorNetwork(blob: Self.triangle + Data([0]))
        }
    }

    @Test("A coordinate that is not finite is refused", arguments: [Float.nan, .infinity, -.infinity])
    func nonFinite(value: Float) throws {
        let blob = Bytes.network(vertices: [(0, value, 0)], segments: [])
        #expect(throws: FigmaBlobError.nonFiniteValue(offset: 16)) {
            try FigmaVectorNetwork(blob: blob)
        }
    }
}
