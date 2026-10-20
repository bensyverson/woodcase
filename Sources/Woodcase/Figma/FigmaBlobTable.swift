//
//  FigmaBlobTable.swift
//  Woodcase
//

import Foundation

/// A Figma message's blob table: the `blobs` array whose entries nodes name by index.
///
/// Geometry travels here rather than in Kiwi fields. A node names a blob with a `uint` —
/// `vectorData.vectorNetworkBlob`, a glyph's or a `Path`'s `commandsBlob` — and the field
/// says which kind it is, so the table decodes on request: ``vectorNetwork(at:)`` or
/// ``path(at:)``. Several nodes or glyphs may name the same blob.
public struct FigmaBlobTable: Friendly {
    /// Each blob's bytes, by index.
    public var blobs: [Data]

    /// A table of `blobs`.
    public init(blobs: [Data] = []) {
        self.blobs = blobs
    }

    /// Reads the table of a decoded `Message`; a message with no `blobs` has an empty one.
    ///
    /// - Throws: ``FigmaBlobError/malformedBlobTable`` when `blobs` is not an array of
    ///   records carrying `bytes`, and ``FigmaBlobError/unsupportedBlobBaseIndex(_:)``
    ///   when the message sets a non-zero `blobBaseIndex`.
    public init(message: KiwiRecord) throws(FigmaBlobError) {
        if let base = message["blobBaseIndex"]?.uintValue, base != 0 {
            throw .unsupportedBlobBaseIndex(base)
        }
        guard let field = message["blobs"] else {
            blobs = []
            return
        }
        guard let entries = field.arrayValue else { throw .malformedBlobTable }
        var blobs: [Data] = []
        blobs.reserveCapacity(entries.count)
        for entry in entries {
            guard let bytes = entry["bytes"]?.bytesValue else { throw .malformedBlobTable }
            blobs.append(bytes)
        }
        self.blobs = blobs
    }

    /// The bytes of blob `index`.
    ///
    /// - Throws: ``FigmaBlobError/blobIndexOutOfRange(index:count:)``.
    public func blob(at index: UInt32) throws(FigmaBlobError) -> Data {
        guard Int(index) < blobs.count else { throw .blobIndexOutOfRange(index: index, count: blobs.count) }
        return blobs[Int(index)]
    }

    /// Blob `index`, decoded as a vector network.
    public func vectorNetwork(at index: UInt32) throws(FigmaBlobError) -> FigmaVectorNetwork {
        try FigmaVectorNetwork(blob: blob(at: index))
    }

    /// Blob `index`, decoded as a command stream: a glyph outline or a `Path`.
    public func path(at index: UInt32) throws(FigmaBlobError) -> FigmaPath {
        try FigmaPath(blob: blob(at: index))
    }
}
