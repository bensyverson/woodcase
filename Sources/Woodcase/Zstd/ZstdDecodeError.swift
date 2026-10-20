//
//  ZstdDecodeError.swift
//  Woodcase
//

/// Why ``ZstdDecoder`` refused its input.
///
/// Every refusal is one of these: the decoder never hands back partial or guessed bytes.
public enum ZstdDecodeError: Error, Friendly {
    /// The input does not begin with a zstd frame's magic number (`28 B5 2F FD`).
    ///
    /// Empty input, zlib or deflate data, a skippable frame and any other format land here.
    case notZstd

    /// The input ends before the frame does.
    case truncated

    /// The frame is malformed, or its content does not match its checksum.
    ///
    /// `code` is zstd's own `ZSTD_ErrorCode` value, for diagnostics.
    case corrupt(code: Int)

    /// The frame decodes to more than `limit` bytes.
    ///
    /// Raised before any output is allocated when the frame header declares its content
    /// size, and as soon as the output passes the limit when it does not. A frame whose
    /// window needs more memory than the decoder allows lands here too.
    case exceedsLimit(limit: Int)

    /// Bytes follow the end of the frame; `count` says how many.
    case trailingBytes(count: Int)
}
