//
//  FigmaBlobBytes.swift
//  WoodcaseTests
//

import Foundation

/// Builds synthetic Figma blobs, little-endian, so the blob tests can state every byte.
struct FigmaBlobBytes {
    /// The bytes written so far.
    var data = Data()

    /// Appends a little-endian `UInt32`.
    mutating func u32(_ value: UInt32) {
        withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
    }

    /// Appends a little-endian IEEE 754 single.
    mutating func f32(_ value: Float) {
        u32(value.bitPattern)
    }

    /// Appends one byte.
    mutating func byte(_ value: UInt8) {
        data.append(value)
    }

    /// One vertex: its style id and position.
    typealias Vertex = (styleID: UInt32, x: Float, y: Float)
    /// One segment: style id, start vertex and tangent, end vertex and tangent.
    typealias Segment = (styleID: UInt32, start: UInt32, tsx: Float, tsy: Float, end: UInt32, tex: Float, tey: Float)
    /// One region: its packed style-and-winding word and its loops of segment indices.
    typealias Region = (word: UInt32, loops: [[UInt32]])

    /// A vector network blob in the layout DocC `FigmaClipboard.md` describes.
    static func network(vertices: [Vertex], segments: [Segment], regions: [Region] = []) -> Data {
        var bytes = FigmaBlobBytes()
        bytes.u32(UInt32(vertices.count))
        bytes.u32(UInt32(segments.count))
        bytes.u32(UInt32(regions.count))
        for vertex in vertices {
            bytes.u32(vertex.styleID)
            bytes.f32(vertex.x)
            bytes.f32(vertex.y)
        }
        for segment in segments {
            bytes.u32(segment.styleID)
            bytes.u32(segment.start)
            bytes.f32(segment.tsx)
            bytes.f32(segment.tsy)
            bytes.u32(segment.end)
            bytes.f32(segment.tex)
            bytes.f32(segment.tey)
        }
        for region in regions {
            bytes.u32(region.word)
            bytes.u32(UInt32(region.loops.count))
            for loop in region.loops {
                bytes.u32(UInt32(loop.count))
                for index in loop {
                    bytes.u32(index)
                }
            }
        }
        return bytes.data
    }

    /// A straight segment from `start` to `end`.
    static func line(_ start: UInt32, _ end: UInt32, styleID: UInt32 = 0) -> Segment {
        (styleID, start, 0, 0, end, 0, 0)
    }

    /// A command stream: each command's opcode, then its little-endian float arguments.
    static func commands(_ commands: [(opcode: UInt8, arguments: [Float])]) -> Data {
        var bytes = FigmaBlobBytes()
        for command in commands {
            bytes.byte(command.opcode)
            for argument in command.arguments {
                bytes.f32(argument)
            }
        }
        return bytes.data
    }
}
