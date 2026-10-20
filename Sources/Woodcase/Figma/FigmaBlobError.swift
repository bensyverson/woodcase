//
//  FigmaBlobError.swift
//  Woodcase
//

/// Why a Figma message's blob table, or one of its blobs, could not be read.
///
/// Blobs are untrusted bytes like the rest of a clipboard, so ``FigmaBlobTable``,
/// ``FigmaVectorNetwork`` and ``FigmaPath`` refuse anything that does not fit the format
/// rather than guess. Offsets count bytes from the start of the blob.
public enum FigmaBlobError: Error, Friendly {
    /// The message's `blobs` field is not an array of `Blob` structs carrying `bytes`.
    case malformedBlobTable
    /// The message sets `blobBaseIndex`, which no capture has done, so how it shifts the
    /// indices nodes store is unknown.
    case unsupportedBlobBaseIndex(UInt32)
    /// A node names blob `index`, and the table holds `count`.
    case blobIndexOutOfRange(index: UInt32, count: Int)

    /// The blob ends inside the value that starts at `offset`.
    case truncated(offset: Int)
    /// The count read at `offset` needs more bytes than remain after it.
    case countExceedsRemainingBytes(count: UInt32, offset: Int)
    /// A vector network's last region ends at `offset`, before the blob does.
    case trailingBytes(offset: Int)
    /// The float at `offset` is a NaN or an infinity.
    case nonFiniteValue(offset: Int)

    /// Segment `segment` names a vertex index past the network's vertices.
    case vertexIndexOutOfRange(segment: Int, vertex: Int)
    /// A loop of region `region` names a segment index past the network's segments.
    case segmentIndexOutOfRange(region: Int, segment: Int)
    /// In loop `loop` of region `region`, the segment at position `segment` shares no
    /// vertex with the point the loop has reached.
    case disconnectedLoop(region: Int, loop: Int, segment: Int)

    /// A command stream holds the opcode `opcode` at `offset`; only 0 through 4 are known.
    case unknownCommand(UInt8, offset: Int)
}
