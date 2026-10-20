//
//  FigmaVectorNetwork.swift
//  Woodcase
//

import Foundation

/// A Figma vector network: the vertices, segments and filled regions of a `VECTOR` node,
/// decoded from the blob its `vectorData.vectorNetworkBlob` names.
public struct FigmaVectorNetwork: Friendly {
    /// A point of the network.
    public struct Vertex: Friendly {
        /// The `styleOverrideTable` entry carrying this vertex's overrides, or 0 for none.
        public var styleID: UInt32
        /// Where the vertex sits, in the node's `vectorData.normalizedSize` space.
        public var position: FigmaPoint

        /// A vertex at `position` with the overrides of `styleID`.
        public init(styleID: UInt32, position: FigmaPoint) {
            self.styleID = styleID
            self.position = position
        }
    }

    /// A straight or cubic edge between two vertices.
    public struct Segment: Friendly {
        /// The `styleOverrideTable` entry carrying this segment's overrides, or 0 for none.
        public var styleID: UInt32
        /// The index of the vertex the segment leaves.
        public var start: Int
        /// The first control point, as an offset from the start vertex.
        public var tangentStart: FigmaPoint
        /// The index of the vertex the segment reaches.
        public var end: Int
        /// The second control point, as an offset from the end vertex.
        public var tangentEnd: FigmaPoint

        /// A segment from vertex `start` to vertex `end`.
        public init(styleID: UInt32, start: Int, tangentStart: FigmaPoint, end: Int, tangentEnd: FigmaPoint) {
            self.styleID = styleID
            self.start = start
            self.tangentStart = tangentStart
            self.end = end
            self.tangentEnd = tangentEnd
        }

        /// Whether both tangents are zero, so the segment is a straight line.
        public var isStraight: Bool {
            tangentStart == .zero && tangentEnd == .zero
        }
    }

    /// A filled area: one or more loops of segments under one winding rule.
    public struct Region: Friendly {
        /// The `styleOverrideTable` entry carrying this region's fill overrides, or 0.
        public var styleID: UInt32
        /// How the loops' overlaps fill.
        public var windingRule: FigmaWindingRule
        /// Each loop's segment indices, in order; a second loop inside the first is a hole.
        public var loops: [[Int]]

        /// A region of `loops`.
        public init(styleID: UInt32, windingRule: FigmaWindingRule, loops: [[Int]]) {
            self.styleID = styleID
            self.windingRule = windingRule
            self.loops = loops
        }
    }

    /// The vertices, by index.
    public private(set) var vertices: [Vertex]
    /// The segments, by index.
    public private(set) var segments: [Segment]
    /// The filled regions.
    public private(set) var regions: [Region]

    /// An empty network.
    public init() {
        vertices = []
        segments = []
        regions = []
    }

    /// A network of these parts, refusing a segment or loop index past the end.
    ///
    /// - Throws: ``FigmaBlobError/vertexIndexOutOfRange(segment:vertex:)`` or
    ///   ``FigmaBlobError/segmentIndexOutOfRange(region:segment:)``.
    public init(vertices: [Vertex], segments: [Segment], regions: [Region]) throws(FigmaBlobError) {
        for (index, segment) in segments.enumerated() {
            for vertex in [segment.start, segment.end] where !vertices.indices.contains(vertex) {
                throw .vertexIndexOutOfRange(segment: index, vertex: vertex)
            }
        }
        for (index, region) in regions.enumerated() {
            for segment in region.loops.joined() where !segments.indices.contains(segment) {
                throw .segmentIndexOutOfRange(region: index, segment: segment)
            }
        }
        self.vertices = vertices
        self.segments = segments
        self.regions = regions
    }

    /// Decodes a `vectorNetworkBlob`: a header of three counts, then the vertices,
    /// segments and regions they count, and nothing after.
    ///
    /// - Throws: ``FigmaBlobError`` when the blob is truncated, a count cannot fit, an
    ///   index points past what it indexes, a float is not finite, or bytes follow the
    ///   last region.
    public init(blob: Data) throws(FigmaBlobError) {
        var reader = FigmaBlobReader(blob)
        let vertexCount = try reader.readUInt32()
        let segmentCount = try reader.readUInt32()
        let regionCount = try reader.readUInt32()
        var remaining = reader.remainingCount
        for (count, offset, size) in [(vertexCount, 0, Self.vertexSize), (segmentCount, 4, Self.segmentSize), (regionCount, 8, Self.minimumRegionSize)] {
            guard Int(count) <= remaining / size else { throw .countExceedsRemainingBytes(count: count, offset: offset) }
            remaining -= Int(count) * size
        }
        var vertices: [Vertex] = []
        vertices.reserveCapacity(Int(vertexCount))
        for _ in 0 ..< vertexCount {
            let styleID = try reader.readUInt32()
            try vertices.append(Vertex(styleID: styleID, position: reader.readPoint()))
        }
        var segments: [Segment] = []
        segments.reserveCapacity(Int(segmentCount))
        for _ in 0 ..< segmentCount {
            let styleID = try reader.readUInt32()
            let start = try reader.readIndex()
            let tangentStart = try reader.readPoint()
            let end = try reader.readIndex()
            try segments.append(Segment(
                styleID: styleID, start: start, tangentStart: tangentStart, end: end, tangentEnd: reader.readPoint()
            ))
        }
        var regions: [Region] = []
        for _ in 0 ..< regionCount {
            let word = try reader.readUInt32()
            var loops: [[Int]] = []
            for _ in try 0 ..< reader.readCount(stride: 4) {
                var loop: [Int] = []
                for _ in try 0 ..< reader.readCount(stride: 4) {
                    try loop.append(reader.readIndex())
                }
                loops.append(loop)
            }
            regions.append(Region(word: word, loops: loops))
        }
        guard reader.isAtEnd else { throw .trailingBytes(offset: reader.offset) }
        try self.init(vertices: vertices, segments: segments, regions: regions)
    }

    /// The bytes of one vertex: a style id and two coordinates.
    static let vertexSize = 12
    /// The bytes of one segment: a style id, two vertex indices and two tangents.
    static let segmentSize = 28
    /// The fewest bytes a region takes: its word and a loop count.
    static let minimumRegionSize = 8
}

extension FigmaVectorNetwork.Region {
    /// A region from its blob word: the winding rule in the low bit (1 nonzero, 0
    /// even-odd), the style id above it.
    init(word: UInt32, loops: [[Int]]) {
        self.init(styleID: word >> 1, windingRule: word & 1 == 1 ? .nonzero : .evenOdd, loops: loops)
    }
}
