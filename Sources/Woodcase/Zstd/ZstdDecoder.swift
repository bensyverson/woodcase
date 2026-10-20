//
//  ZstdDecoder.swift
//  Woodcase
//

internal import CZstdDecode
import Foundation

/// Decodes one zstd frame, refusing anything over a size cap.
///
/// zstd is the compression Figma's clipboard payload uses, and no Apple API decodes it, so
/// Woodcase vendors zstd's own decode-only library (the `CZstdDecode` target) and wraps it
/// here. The input may come from a hostile clipboard, so the decoder trusts nothing:
///
/// - The input must be exactly one zstd frame — anything else, before or after it, is an
///   error rather than skipped.
/// - When the frame header declares its content size, a size over ``maxDecodedSize`` is
///   refused before anything is allocated. When it does not, the frame is streamed and
///   refused as soon as the output passes the cap.
/// - Each failure is a ``ZstdDecodeError``; a zero return code is never taken as success
///   on its own.
///
/// ```swift
/// let message = try ZstdDecoder(maxDecodedSize: 64 << 20).decode(chunk)
/// ```
public struct ZstdDecoder: Friendly {
    /// The most bytes a frame may decode to. Never negative.
    public var maxDecodedSize: Int

    /// Creates a decoder that refuses frames decoding to more than `maxDecodedSize` bytes.
    ///
    /// - Precondition: `maxDecodedSize` is not negative.
    public init(maxDecodedSize: Int) {
        precondition(maxDecodedSize >= 0, "ZstdDecoder's cap cannot be negative")
        self.maxDecodedSize = maxDecodedSize
    }

    /// Decodes `frame`, which must hold exactly one zstd frame, to its bytes.
    ///
    /// - Throws: ``ZstdDecodeError`` when the input is not a zstd frame, is truncated or
    ///   corrupt, has bytes after the frame, or decodes to more than ``maxDecodedSize``.
    public func decode(_ frame: Data) throws(ZstdDecodeError) -> Data {
        guard frame.starts(with: Self.magic) else { throw .notZstd }
        let result: Result<Data, ZstdDecodeError> = frame.withUnsafeBytes { input in
            Result { () throws(ZstdDecodeError) -> Data in try decode(input) }
        }
        return try result.get()
    }

    /// The four bytes every zstd frame begins with: `0xFD2FB528`, little-endian.
    static let magic: [UInt8] = [0x28, 0xB5, 0x2F, 0xFD]

    private func decode(_ input: UnsafeRawBufferPointer) throws(ZstdDecodeError) -> Data {
        guard let base = input.baseAddress else { throw .notZstd }
        let frameSize = ZSTD_findFrameCompressedSize(base, input.count)
        try check(frameSize)
        guard frameSize == input.count else {
            throw .trailingBytes(count: input.count - frameSize)
        }
        let frame = UnsafeRawBufferPointer(start: base, count: frameSize)
        let declared = ZSTD_getFrameContentSize(base, frameSize)
        switch declared {
        case Self.contentSizeError:
            throw .corrupt(code: Int(ZSTD_error_corruption_detected.rawValue))
        case Self.contentSizeUnknown:
            return try stream(frame)
        default:
            guard declared <= UInt64(maxDecodedSize) else {
                throw .exceedsLimit(limit: maxDecodedSize)
            }
            return try decodeWhole(frame, size: Int(declared))
        }
    }

    /// Decodes a frame whose header declared `size` bytes, into a buffer of exactly that size.
    private func decodeWhole(
        _ frame: UnsafeRawBufferPointer, size: Int
    ) throws(ZstdDecodeError) -> Data {
        guard let context = ZSTD_createDCtx() else { throw .exceedsLimit(limit: maxDecodedSize) }
        defer { ZSTD_freeDCtx(context) }
        // A zero-size frame still gets a byte of room, so the destination is never NULL.
        var output = Data(count: max(size, 1))
        let written = output.withUnsafeMutableBytes { destination in
            ZSTD_decompressDCtx(
                context, destination.baseAddress, destination.count,
                frame.baseAddress, frame.count
            )
        }
        try check(written)
        // zstd checks the produced size against the header; this guards that promise.
        guard written == size else {
            throw .corrupt(code: Int(ZSTD_error_corruption_detected.rawValue))
        }
        return output.prefix(size)
    }

    /// Throws the ``ZstdDecodeError`` for `result` when zstd reports it as an error.
    func check(_ result: Int) throws(ZstdDecodeError) {
        guard ZSTD_isError(result) != 0 else { return }
        let code = ZSTD_getErrorCode(result)
        switch code {
        case ZSTD_error_srcSize_wrong:
            throw .truncated
        case ZSTD_error_prefix_unknown:
            throw .notZstd
        case ZSTD_error_frameParameter_windowTooLarge, ZSTD_error_memory_allocation:
            throw .exceedsLimit(limit: maxDecodedSize)
        default:
            throw .corrupt(code: Int(code.rawValue))
        }
    }

    /// `ZSTD_CONTENTSIZE_UNKNOWN`: the header does not declare the content size.
    private static let contentSizeUnknown = UInt64.max
    /// `ZSTD_CONTENTSIZE_ERROR`: the header could not be read.
    private static let contentSizeError = UInt64.max - 1
}
