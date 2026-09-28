//
//  ZlibEncoder.swift
//  Woodcase
//

/// Compresses bytes into a zlib stream (RFC 1950) in pure Swift, for the one place that
/// needs it: ``PortablePNGEncoder``'s image data.
///
/// Foundation has no zlib on Linux and Apple's Compression framework does not exist
/// there, so the PNG writer the React emitter uses carries its own. It is deliberately
/// small: a single deflate block (RFC 1951) with a dynamic Huffman code over the 256 byte
/// values and no LZ77 back-references. A PNG row filter turns a smooth image into a
/// stream of small residuals, and entropy-coding those is where nearly all of the gain
/// is for the low-frequency rasters it compresses; back-references would add a match
/// finder for a few percent more.
///
/// The output is deterministic, so a golden file that embeds it is stable.
enum ZlibEncoder {
    /// The literal/length alphabet this encoder uses: the 256 byte values and end-of-block.
    static let literalCount = 257

    /// The end-of-block symbol.
    static let endOfBlock = 256

    /// Deflate's limit on a Huffman code's length, in bits.
    static let maximumCodeLength = 15

    /// The order in which a dynamic block lists the code-length alphabet's lengths
    /// (RFC 1951 §3.2.7).
    static let codeLengthOrder = [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15]

    /// Compresses `bytes` into a complete zlib stream: header, one final deflate block,
    /// and the Adler-32 checksum.
    ///
    /// - Parameter bytes: The data to compress.
    /// - Returns: The zlib stream.
    static func compress(_ bytes: [UInt8]) -> [UInt8] {
        var frequencies = [Int](repeating: 0, count: literalCount)
        for byte in bytes {
            frequencies[Int(byte)] += 1
        }
        frequencies[endOfBlock] = 1
        let lengths = HuffmanCode.lengths(for: frequencies, limit: maximumCodeLength)
        let codes = HuffmanCode.canonicalCodes(for: lengths)

        var writer = BitWriter()
        writer.write(1, count: 1) // BFINAL: the only block
        writer.write(2, count: 2) // BTYPE: dynamic Huffman
        writer.write(UInt32(literalCount - 257), count: 5) // HLIT
        writer.write(2 - 1, count: 5) // HDIST: two distance codes
        writer.write(UInt32(codeLengthOrder.count - 4), count: 4) // HCLEN

        // The code-length alphabet: symbols 0–15 at four bits each is a complete code in
        // which each symbol's code is its own value, so no run-length symbols are needed.
        for symbol in codeLengthOrder {
            writer.write(symbol < 16 ? 4 : 0, count: 3)
        }
        for length in lengths {
            writer.writeHuffman(UInt32(length), length: 4)
        }
        // No distances are used, but two one-bit distance codes keep the code complete,
        // which every inflater accepts.
        writer.writeHuffman(1, length: 4)
        writer.writeHuffman(1, length: 4)

        for byte in bytes {
            writer.writeHuffman(codes[Int(byte)], length: lengths[Int(byte)])
        }
        writer.writeHuffman(codes[endOfBlock], length: lengths[endOfBlock])

        // CMF 0x78: deflate with a 32 KiB window. FLG 0x01: fastest level, and the check
        // bits that make the 16-bit header a multiple of 31.
        var stream: [UInt8] = [0x78, 0x01]
        stream += writer.finish()
        let checksum = adler32(bytes)
        stream += [24, 16, 8, 0].map { UInt8(truncatingIfNeeded: checksum >> $0) }
        return stream
    }

    /// The Adler-32 checksum zlib appends (RFC 1950 §8).
    static func adler32(_ bytes: [UInt8]) -> UInt32 {
        let modulus: UInt32 = 65521
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in bytes {
            a = (a + UInt32(byte)) % modulus
            b = (b + a) % modulus
        }
        return b << 16 | a
    }
}
