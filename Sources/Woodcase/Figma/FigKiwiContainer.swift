//
//  FigKiwiContainer.swift
//  Woodcase
//

import Foundation

/// The binary Figma puts on the clipboard and inside a `.fig`'s `canvas.fig`: an 8-byte
/// prelude, a little-endian `UInt32` version, then chunks, each a little-endian `UInt32`
/// length and that many bytes.
///
/// In a clipboard payload chunk 0 is the Kiwi schema (raw deflate) and chunk 1 the
/// message (zstd); ``FigmaClipboardDecoder`` decompresses them. This type only frames the
/// bytes: every length is checked against the bytes that remain, so a hostile length can
/// neither read past the input nor allocate beyond it.
public struct FigKiwiContainer: Friendly {
    /// The 8-byte magic a container opens with; it names the editor in a file, while a
    /// clipboard payload always says ``design``.
    public enum Prelude: String, Friendly, CaseIterable {
        /// `fig-kiwi`: a Design file, and every clipboard payload.
        case design = "fig-kiwi"
        /// `fig-jam.`: a FigJam file.
        case figJam = "fig-jam."
        /// `fig-deck`: a Slides file.
        case slides = "fig-deck"
    }

    /// The prelude the container opens with.
    public var prelude: Prelude
    /// The container version. It varies by file and over time (101 and 106 so far) and
    /// does not identify the schema.
    public var version: UInt32
    /// The chunks, still compressed, in order.
    public var chunks: [Data]

    /// Creates a container from its parts.
    public init(prelude: Prelude, version: UInt32, chunks: [Data]) {
        self.prelude = prelude
        self.version = version
        self.chunks = chunks
    }

    /// Reads a container from `data`, which must end exactly where its last chunk does.
    ///
    /// - Throws: ``FigmaDecodeError/unknownPrelude``, ``FigmaDecodeError/truncatedHeader``,
    ///   ``FigmaDecodeError/truncatedChunkLength(index:)`` or
    ///   ``FigmaDecodeError/chunkExceedsRemainingBytes(index:length:remaining:)``.
    public init(_ data: Data) throws(FigmaDecodeError) {
        let bytes = [UInt8](data)
        guard bytes.count >= 8, let prelude = Prelude(rawValue: String(decoding: bytes[..<8], as: UTF8.self)) else {
            throw .unknownPrelude
        }
        guard bytes.count >= 12 else { throw .truncatedHeader }
        var chunks: [Data] = []
        var offset = 12
        while offset < bytes.count {
            guard bytes.count - offset >= 4 else { throw .truncatedChunkLength(index: chunks.count) }
            let length = Self.littleEndian(bytes, at: offset)
            offset += 4
            let remaining = bytes.count - offset
            guard UInt64(length) <= UInt64(remaining) else {
                throw .chunkExceedsRemainingBytes(index: chunks.count, length: length, remaining: remaining)
            }
            chunks.append(Data(bytes[offset ..< offset + Int(length)]))
            offset += Int(length)
        }
        self.init(prelude: prelude, version: Self.littleEndian(bytes, at: 8), chunks: chunks)
    }

    /// The little-endian `UInt32` at `offset`; the caller has checked four bytes remain.
    private static func littleEndian(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        (0 ..< 4).reduce(UInt32(0)) { value, index in value | UInt32(bytes[offset + index]) << (index * 8) }
    }
}
