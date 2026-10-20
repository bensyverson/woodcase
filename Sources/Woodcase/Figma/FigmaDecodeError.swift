//
//  FigmaDecodeError.swift
//  Woodcase
//

/// Why a Figma clipboard payload could not be read.
///
/// Every refusal of ``FigmaClipboardPayload``, ``FigKiwiContainer`` and
/// ``FigmaClipboardDecoder`` is one of these: a clipboard is untrusted input, so a payload
/// that does not match the format is refused, never guessed at.
public enum FigmaDecodeError: Error, Friendly {
    /// One of the two sections a Figma clipboard HTML payload carries.
    public enum Section: String, Friendly {
        /// `data-metadata`: the `(figmeta)` JSON.
        case metadata
        /// `data-buffer`: the `(figma)` fig-kiwi binary.
        case buffer
    }

    /// The HTML has no attribute carrying `section` between its markers.
    case missingSection(Section)
    /// `section`'s text between its markers is not base64.
    case invalidBase64(Section)
    /// The `(figmeta)` section is not a JSON object of the expected shape.
    case invalidMetadata

    /// The binary does not begin with a known 8-byte prelude, such as `fig-kiwi`.
    case unknownPrelude
    /// The binary ends before its prelude and version do.
    case truncatedHeader
    /// The binary ends inside chunk `index`'s 4-byte length.
    case truncatedChunkLength(index: Int)
    /// Chunk `index` declares `length` bytes when only `remaining` follow its length field.
    case chunkExceedsRemainingBytes(index: Int, length: UInt32, remaining: Int)
    /// The container holds `found` chunks; a clipboard payload needs a schema and a message.
    case missingChunks(found: Int)

    /// The schema chunk is not a raw deflate stream within the schema cap.
    case schemaDecompression(DeflateDecodeError)
    /// The message chunk is not a zstd frame within the message cap.
    case messageDecompression(ZstdDecodeError)
    /// The inflated schema is not a binary Kiwi schema.
    case schemaDecoding(KiwiDecodingError)
    /// The decompressed message does not decode as the schema's root message.
    case messageDecoding(KiwiDecodingError)
}
