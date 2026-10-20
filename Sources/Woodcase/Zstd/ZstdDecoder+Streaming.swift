//
//  ZstdDecoder+Streaming.swift
//  Woodcase
//

internal import CZstdDecode
import Foundation

extension ZstdDecoder {
    /// The smallest window limit a stream gets, as a power of two: 8 MiB, the window zstd's
    /// levels up to 19 choose when they cannot know the content size. A smaller cap still
    /// admits such a stream; its output is held to the cap regardless.
    static let minimumWindowLog = 23

    /// The largest window limit a stream gets: zstd's own default ceiling, 128 MiB
    /// (`ZSTD_WINDOWLOG_LIMIT_DEFAULT`).
    static let maximumWindowLog = 27

    /// The window limit for this decoder's streams: the cap rounded up to a power of two,
    /// within ``minimumWindowLog`` and ``maximumWindowLog``. A window is allocated before
    /// any output, so this bounds the memory a hostile frame costs up front.
    var windowLogMax: Int {
        let capLog = Int.bitWidth - max(maxDecodedSize - 1, 0).leadingZeroBitCount
        return min(max(capLog, Self.minimumWindowLog), Self.maximumWindowLog)
    }

    /// Decodes a frame that does not declare its content size, a chunk at a time, refusing
    /// it once the output passes ``maxDecodedSize``.
    func stream(_ frame: UnsafeRawBufferPointer) throws(ZstdDecodeError) -> Data {
        guard let context = ZSTD_createDStream() else {
            throw .exceedsLimit(limit: maxDecodedSize)
        }
        defer { ZSTD_freeDStream(context) }
        try check(ZSTD_DCtx_setParameter(context, ZSTD_d_windowLogMax, Int32(windowLogMax)))
        var input = ZSTD_inBuffer(src: frame.baseAddress, size: frame.count, pos: 0)
        var chunk = [UInt8](repeating: 0, count: ZSTD_DStreamOutSize())
        var decoded = Data()
        while true {
            let (remaining, produced) = chunk.withUnsafeMutableBytes { buffer in
                var output = ZSTD_outBuffer(dst: buffer.baseAddress, size: buffer.count, pos: 0)
                let remaining = ZSTD_decompressStream(context, &output, &input)
                return (remaining, output.pos)
            }
            try check(remaining)
            guard decoded.count + produced <= maxDecodedSize else {
                throw .exceedsLimit(limit: maxDecodedSize)
            }
            decoded.append(contentsOf: chunk[..<produced])
            if remaining == 0 { return decoded }
            // Input spent and the output not full: zstd wants bytes the frame lacks.
            if input.pos == input.size, produced < chunk.count { throw .truncated }
        }
    }
}
