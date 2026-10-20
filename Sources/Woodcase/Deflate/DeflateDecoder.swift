//
//  DeflateDecoder.swift
//  Woodcase
//

import Compression
import Foundation

/// Inflates raw deflate (RFC 1951, no zlib or gzip wrapper), refusing anything over a
/// size cap.
///
/// Figma's clipboard payload stores its Kiwi schema as raw deflate. This wraps Apple's
/// Compression framework (`COMPRESSION_ZLIB`, which is raw deflate) the way ``ZstdDecoder``
/// wraps zstd. The input may come from a hostile clipboard, so the decoder trusts nothing:
///
/// - It streams (`compression_stream`), so success is the framework reporting the final
///   block's end, never a byte count: `compression_decode_buffer`'s count cannot tell an
///   error from empty output, nor a full buffer from a longer stream.
/// - Output past ``maxDecodedSize`` is refused as soon as a step produces it, so a
///   decompression bomb costs at most the cap plus one step's buffer.
/// - A stream that stops before its final block's end is an error.
///
/// What the framework does not check, this cannot: deflate has no checksum, a stored
/// block's length complement goes unchecked, and bytes after the final block are consumed
/// silently (all verified on macOS 27). So a corrupted stream can inflate to wrong bytes,
/// and the caller's own decode of the output — a Kiwi schema, for Figma — is the real
/// validity check.
///
/// ```swift
/// let schema = try DeflateDecoder(maxDecodedSize: 16 << 20).decode(chunk)
/// ```
public struct DeflateDecoder: Friendly {
    /// The most bytes a stream may inflate to. Never negative.
    public var maxDecodedSize: Int

    /// Creates a decoder that refuses streams inflating to more than `maxDecodedSize` bytes.
    ///
    /// - Precondition: `maxDecodedSize` is not negative.
    public init(maxDecodedSize: Int) {
        precondition(maxDecodedSize >= 0, "DeflateDecoder's cap cannot be negative")
        self.maxDecodedSize = maxDecodedSize
    }

    /// Inflates `stream`, which must hold one raw deflate stream.
    ///
    /// - Throws: ``DeflateDecodeError`` when the stream is empty, truncated or malformed,
    ///   or inflates to more than ``maxDecodedSize``.
    public func decode(_ stream: Data) throws(DeflateDecodeError) -> Data {
        guard !stream.isEmpty else { throw .malformed }
        let state = UnsafeMutablePointer<compression_stream>.allocate(capacity: 1)
        defer { state.deallocate() }
        // The framework refuses to start a stream only when it cannot allocate one; no input
        // has been read, so the stream is reported as undecodable rather than as too large.
        guard compression_stream_init(state, COMPRESSION_STREAM_DECODE, COMPRESSION_ZLIB) == COMPRESSION_STATUS_OK else {
            throw .malformed
        }
        defer { compression_stream_destroy(state) }
        let result: Result<Data, DeflateDecodeError> = stream.withUnsafeBytes { input in
            Result { () throws(DeflateDecodeError) -> Data in try inflate(input, with: state) }
        }
        return try result.get()
    }

    /// The bytes each `compression_stream_process` step may write.
    static let stepSize = 64 << 10

    /// Runs `state` over `input` until the framework reports the stream's end.
    private func inflate(
        _ input: UnsafeRawBufferPointer, with state: UnsafeMutablePointer<compression_stream>
    ) throws(DeflateDecodeError) -> Data {
        guard let base = input.baseAddress else { throw .malformed }
        state.pointee.src_ptr = base.assumingMemoryBound(to: UInt8.self)
        state.pointee.src_size = input.count
        var step = [UInt8](repeating: 0, count: Self.stepSize)
        var decoded = Data()
        while true {
            let (status, produced) = step.withUnsafeMutableBufferPointer { buffer in
                state.pointee.dst_ptr = buffer.baseAddress!
                state.pointee.dst_size = buffer.count
                let status = compression_stream_process(state, Int32(COMPRESSION_STREAM_FINALIZE.rawValue))
                return (status, buffer.count - state.pointee.dst_size)
            }
            guard produced <= maxDecodedSize - decoded.count else { throw .exceedsLimit(limit: maxDecodedSize) }
            decoded.append(contentsOf: step[..<produced])
            switch status {
            case COMPRESSION_STATUS_END:
                return decoded
            case COMPRESSION_STATUS_OK:
                // The step not filled, yet no end: the framework has stopped, on input cut
                // short or malformed, and another step would make no progress.
                if produced < step.count { throw .malformed }
            default:
                throw .malformed
            }
        }
    }
}
