//
//  ZlibEncoderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

#if canImport(Compression)
    import Compression
#endif

/// The Foundation-only zlib writer behind ``PortablePNGEncoder``, checked against an
/// independent inflater (Apple's Compression framework) so a bug cannot hide in a
/// round trip through its own reader.
struct ZlibEncoderTests {
    @Test("The stream opens with a valid zlib header and closes with the Adler-32 of the input")
    func headerAndTrailer() throws {
        let input = Array("Wikipedia".utf8)
        let stream = ZlibEncoder.compress(input)
        try #require(stream.count > 6)
        let header = Int(stream[0]) * 256 + Int(stream[1])
        #expect(stream[0] == 0x78)
        #expect(header % 31 == 0)
        // Adler-32 of "Wikipedia" is 0x11E60398, big-endian at the end.
        #expect(Array(stream.suffix(4)) == [0x11, 0xE6, 0x03, 0x98])
    }

    #if canImport(Compression)
        @Test("An independent inflater recovers the input", arguments: ZlibEncoderTests.samples)
        func roundTrips(sample: Sample) throws {
            let stream = ZlibEncoder.compress(sample.bytes)
            let inflated = try #require(Self.inflate(stream, expectedCount: sample.bytes.count))
            #expect(inflated == sample.bytes)
        }
    #endif

    @Test("Skewed, low-entropy input comes out smaller than it went in")
    func compressesSmoothData() {
        let input = (0 ..< 20000).map { UInt8($0 % 7 == 0 ? 1 : 0) }
        let stream = ZlibEncoder.compress(input)
        #expect(stream.count > 6)
        #expect(stream.count < input.count / 4)
    }

    // MARK: - Samples

    /// One named input.
    struct Sample: CustomTestStringConvertible {
        let name: String
        let bytes: [UInt8]
        var testDescription: String {
            name
        }
    }

    static let samples: [Sample] = [
        Sample(name: "empty", bytes: []),
        Sample(name: "one byte", bytes: [42]),
        Sample(name: "one symbol repeated", bytes: Array(repeating: 7, count: 1000)),
        Sample(name: "every byte value", bytes: (0 ..< 1024).map { UInt8($0 % 256) }),
        Sample(name: "pseudo-random", bytes: pseudoRandom(count: 5000)),
        // Fibonacci frequencies make an unconstrained Huffman tree ~20 deep, past
        // deflate's 15-bit limit, so this exercises the length limiter.
        Sample(name: "Fibonacci frequencies", bytes: fibonacciBytes()),
    ]

    private static func pseudoRandom(count: Int) -> [UInt8] {
        var state: UInt32 = 0x1234_5678
        return (0 ..< count).map { _ in
            state = state &* 1_664_525 &+ 1_013_904_223
            return UInt8(truncatingIfNeeded: state >> 24)
        }
    }

    private static func fibonacciBytes() -> [UInt8] {
        var counts = [1, 1]
        while counts.count < 24 {
            counts.append(counts[counts.count - 1] + counts[counts.count - 2])
        }
        return counts.enumerated().flatMap { symbol, count in
            Array(repeating: UInt8(symbol), count: count)
        }
    }

    #if canImport(Compression)
        /// Inflates a zlib stream with the Compression framework, which reads raw deflate:
        /// the two-byte header and the Adler-32 trailer are stripped first.
        private static func inflate(_ stream: [UInt8], expectedCount: Int) -> [UInt8]? {
            guard stream.count > 6 else { return nil }
            let raw = Array(stream.dropFirst(2).dropLast(4))
            let capacity = expectedCount + 64
            var output = [UInt8](repeating: 0, count: capacity)
            let written = output.withUnsafeMutableBufferPointer { destination in
                raw.withUnsafeBufferPointer { source in
                    compression_decode_buffer(
                        destination.baseAddress!, capacity,
                        source.baseAddress!, raw.count,
                        nil, COMPRESSION_ZLIB
                    )
                }
            }
            guard written == expectedCount || (expectedCount == 0 && written == 0) else { return nil }
            return Array(output.prefix(written))
        }
    #endif
}
