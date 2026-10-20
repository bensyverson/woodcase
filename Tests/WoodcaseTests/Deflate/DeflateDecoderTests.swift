//
//  DeflateDecoderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `DeflateDecoder` inflates raw deflate (RFC 1951, no zlib header) to its exact bytes.
///
/// The hex streams were produced by Python's zlib (`compressobj(level, DEFLATED, -15)`,
/// `Z_FIXED` for the fixed-code ones) and checked with `zlib.decompress(s, -15)`, so they do not
/// come from the framework the decoder wraps.
struct DeflateDecoderTests {
    static let roomy = DeflateDecoder(maxDecodedSize: 16 << 20)

    /// Bytes from a hex string; the vectors are short and trusted, so a bad digit traps.
    static func hex(_ string: String) -> Data {
        var bytes: [UInt8] = []
        var index = string.startIndex
        while index < string.endIndex {
            let next = string.index(index, offsetBy: 2)
            bytes.append(UInt8(string[index ..< next], radix: 16)!)
            index = next
        }
        return Data(bytes)
    }

    /// zlib, level 9: an empty input is one fixed block holding only end-of-block.
    static let empty = hex("0300")

    /// zlib `Z_FIXED`: "Woodcase reads Figma."
    static let fixed = hex("0bcfcf4f494e2c4e55284a4d4c295670cb4ccf4dd40300")

    /// zlib `Z_FIXED`: 1,000 × "a", one literal and overlapping distance-1 copies.
    static let run = hex("4b4c1c05a360140c770000")

    /// zlib level 9, one dynamic block: ``squares``.
    static let dynamic = hex(
        "5d92310e43310843afc211022424514e53a91d3ab655ef5ffc27dc3108d9cf264d3eafefedfdb8cb"
            + "f323ed88d6b71eb1faee47bcbef7914efb7164d4818d2351079e1b93245363d541a4c9ae839514"
            + "dac8a60194490d5b04ab3d95d4992fdd949177122943835a8373608bc06d418bd0dde0b8392f3a"
            + "24fa0e7a23fadeb1c555afd432a21f968e46f4632697117d80de883eae2da29f9716d1cfcb91ab"
            + "079713fd06bd13fd4646e7ee1baa702ebfa131e7f615c5fae053228107cf7026a708eab8a6afbf"
            + "9bc39742e8c0dff801"
    )

    /// What ``dynamic`` holds: "0 squared is 0; 1 squared is 1; …" for 0 through 39.
    static let squares = Data((0 ..< 40).map { "\($0) squared is \($0 * $0); " }.joined().utf8)

    // MARK: - Block types

    @Test("An empty stream inflates to no bytes")
    func emptyStream() throws {
        #expect(try Self.roomy.decode(Self.empty) == Data())
    }

    @Test("A stored block inflates to its bytes")
    func storedBlock() throws {
        let stream = Self.hex("0105" + "00faff") + Data("hello".utf8)
        #expect(try Self.roomy.decode(stream) == Data("hello".utf8))
    }

    @Test("A fixed-code block inflates to its bytes")
    func fixedBlock() throws {
        #expect(try Self.roomy.decode(Self.fixed) == Data("Woodcase reads Figma.".utf8))
    }

    @Test("A dynamic-code block inflates to its bytes")
    func dynamicBlock() throws {
        #expect(try Self.roomy.decode(Self.dynamic) == Self.squares)
    }

    @Test("Overlapping back-references repeat the bytes they copy")
    func overlappingCopy() throws {
        #expect(try Self.roomy.decode(Self.run) == Data(repeating: UInt8(ascii: "a"), count: 1000))
    }

    @Test("A non-final stored block followed by a fixed block inflates to both")
    func multipleBlocks() throws {
        let stored = Self.hex("000d00f2ff") + Data("stored part, ".utf8)
        let decoded = try Self.roomy.decode(stored + Self.fixed)
        #expect(decoded == Data("stored part, Woodcase reads Figma.".utf8))
    }

    @Test("Output exactly at the cap is allowed")
    func outputAtCap() throws {
        let decoder = DeflateDecoder(maxDecodedSize: 1000)
        #expect(try decoder.decode(Self.run).count == 1000)
    }

    @Test("The longest distance (32,768) and length (258) decode")
    func longestDistance() throws {
        var writer = DeflateBitWriter()
        writer.header(final: false, type: 0)
        writer.write(0, bits: 5) // pad the stored block's header to a byte
        let filler = Data((0 ..< 32768).map { UInt8(truncatingIfNeeded: $0 &* 7) })
        var stream = writer.data
        stream += Self.hex("0080ff7f") + filler
        var tail = DeflateBitWriter()
        tail.header(final: true, type: 1)
        tail.fixedLiteral(285) // length 258, no extra bits
        tail.fixedDistance(29) // distances 24,577–32,768: 13 extra bits
        tail.write(8191, bits: 13)
        tail.fixedLiteral(256)
        stream += tail.data
        let decoded = try Self.roomy.decode(stream)
        #expect(decoded.count == 32768 + 258)
        #expect(decoded.suffix(258) == filler.prefix(258))
    }

    // MARK: - Round trips through Foundation's deflate

    @Test("Foundation's deflate of varied inputs inflates back to them", arguments: [
        0, 1, 100, 65535, 65536, 300_000,
    ])
    func foundationRoundTrip(size: Int) throws {
        var generator = SeededRandomNumberGenerator(seed: UInt64(size))
        let random = Data((0 ..< size).map { _ in UInt8(truncatingIfNeeded: generator.next()) })
        let words = ["frame", "fill", "stroke", "layout", "vector", "text", " ", "\n"]
        let text = Data((0 ..< size).map { _ in words[Int(generator.next() % 8)] }.joined().utf8.prefix(size))
        for input in [random, text, Data(repeating: 0, count: size)] {
            let compressed = try (input as NSData).compressed(using: .zlib) as Data
            #expect(try Self.roomy.decode(compressed) == input)
        }
    }
}
