//
//  DeflateDecoderHostileTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `DeflateDecoder` refuses malformed or oversized input with a typed error: it never
/// traps, never loops forever and never returns more than its cap.
///
/// The streams are hand-built with ``DeflateBitWriter``, each breaking one rule of RFC 1951,
/// so these prove that Apple's decoder, as wrapped, reports the break instead of
/// inflating past it. Two breaks it does not report — a stored block's bad length
/// complement and bytes after the final block — are covered where the Figma decoder's
/// Kiwi step catches them (`FigmaClipboardDecoderTests`).
struct DeflateDecoderHostileTests {
    private static let roomy = DeflateDecoderTests.roomy

    private static func expectError(_ expected: DeflateDecodeError, decoding stream: Data) {
        #expect(throws: expected) { try roomy.decode(stream) }
    }

    // MARK: - Framing

    @Test("Empty input is refused")
    func emptyInput() {
        Self.expectError(.malformed, decoding: Data())
    }

    @Test("Block type 3 is refused")
    func reservedBlockType() {
        Self.expectError(.malformed, decoding: DeflateDecoderTests.hex("07"))
    }

    @Test("A stored block shorter than its length is refused")
    func storedTruncated() {
        Self.expectError(.malformed, decoding: DeflateDecoderTests.hex("010500faff6865"))
    }

    @Test("A stream that stops before its final block is refused")
    func missingFinalBlock() {
        let stored = DeflateDecoderTests.hex("000d00f2ff") + Data("stored part, ".utf8)
        Self.expectError(.malformed, decoding: stored)
    }

    @Test("Output past the cap is refused")
    func exceedsCap() {
        let decoder = DeflateDecoder(maxDecodedSize: 999)
        #expect(throws: DeflateDecodeError.exceedsLimit(limit: 999)) {
            try decoder.decode(DeflateDecoderTests.run)
        }
    }

    // MARK: - Symbols

    @Test("A distance reaching before the output's start is refused")
    func distanceTooFar() {
        var writer = DeflateBitWriter()
        writer.header(final: true, type: 1)
        writer.fixedLiteral(Int(UInt8(ascii: "a")))
        writer.fixedLiteral(257) // length 3
        writer.fixedDistance(1) // distance 2
        writer.fixedLiteral(256)
        Self.expectError(.malformed, decoding: writer.data)
    }

    @Test("Length symbols 286 and 287 are refused", arguments: [286, 287])
    func invalidLengthSymbol(symbol: Int) {
        var writer = DeflateBitWriter()
        writer.header(final: true, type: 1)
        writer.fixedLiteral(Int(UInt8(ascii: "a")))
        writer.fixedLiteral(symbol)
        writer.fixedLiteral(256)
        Self.expectError(.malformed, decoding: writer.data)
    }

    @Test("Distance symbols 30 and 31 are refused", arguments: [30, 31])
    func invalidDistanceSymbol(symbol: Int) {
        var writer = DeflateBitWriter()
        writer.header(final: true, type: 1)
        writer.fixedLiteral(Int(UInt8(ascii: "a")))
        writer.fixedLiteral(257)
        writer.fixedDistance(symbol)
        writer.fixedLiteral(256)
        Self.expectError(.malformed, decoding: writer.data)
    }

    // MARK: - Dynamic headers

    @Test("More than 286 literal/length codes are refused")
    func tooManyLiteralCodes() {
        var writer = DeflateBitWriter()
        writer.header(final: true, type: 2)
        writer.write(30, bits: 5) // HLIT: 287 codes
        writer.write(0, bits: 5)
        writer.write(0, bits: 4)
        writer.write(0, bits: 16)
        Self.expectError(.malformed, decoding: writer.data)
    }

    @Test("An over-subscribed code-length code is refused")
    func overSubscribedCodeLengthCode() {
        var writer = DeflateBitWriter()
        writer.header(final: true, type: 2)
        writer.write(0, bits: 5)
        writer.write(0, bits: 5)
        writer.write(15, bits: 4) // HCLEN: all 19
        for _ in 0 ..< 19 {
            writer.write(1, bits: 3)
        }
        writer.write(0, bits: 16)
        Self.expectError(.malformed, decoding: writer.data)
    }

    @Test("An incomplete code-length code is refused")
    func incompleteCodeLengthCode() {
        var writer = DeflateBitWriter()
        writer.header(final: true, type: 2)
        writer.write(0, bits: 5)
        writer.write(0, bits: 5)
        writer.write(0, bits: 4) // HCLEN: lengths for 16, 17, 18 and 0
        for length: UInt32 in [0, 0, 0, 2] { // one two-bit code: three codes unused
            writer.write(length, bits: 3)
        }
        writer.write(0, bits: 16)
        Self.expectError(.malformed, decoding: writer.data)
    }

    @Test("Repeating the previous length before any length is refused")
    func repeatWithoutPrevious() {
        var writer = DeflateBitWriter()
        writer.header(final: true, type: 2)
        writer.write(0, bits: 5)
        writer.write(0, bits: 5)
        writer.write(0, bits: 4) // HCLEN: lengths for 16, 17, 18 and 0
        for length: UInt32 in [1, 0, 0, 1] {
            writer.write(length, bits: 3)
        }
        writer.writeCode(1, length: 1) // symbol 16 first
        writer.write(0, bits: 16)
        Self.expectError(.malformed, decoding: writer.data)
    }

    @Test("A literal/length code with no end-of-block code is refused")
    func missingEndOfBlock() {
        var writer = DeflateBitWriter()
        writer.header(final: true, type: 2)
        writer.write(0, bits: 5) // 257 literal/length codes
        writer.write(0, bits: 5) // 1 distance code
        writer.write(14, bits: 4) // HCLEN: 18 entries, through symbol 1
        // Order: 16 17 18 0 8 7 9 6 10 5 11 4 12 3 13 2 14 1. Symbols 0 and 1 get one
        // bit each, so a 0 bit writes length 0 and a 1 bit writes length 1.
        for symbol in [16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1] {
            writer.write(symbol == 0 || symbol == 1 ? 1 : 0, bits: 3)
        }
        writer.writeCode(1, length: 1) // literal 0: length 1
        writer.writeCode(1, length: 1) // literal 1: length 1
        for _ in 2 ..< 258 { // the rest, end-of-block and the distance code: length 0
            writer.writeCode(0, length: 1)
        }
        writer.write(0, bits: 16)
        Self.expectError(.malformed, decoding: writer.data)
    }

    // MARK: - Fuzz

    @Test("Random and mutated streams never trap and never pass the cap")
    func fuzz() {
        let decoder = DeflateDecoder(maxDecodedSize: 4096)
        var generator = SeededRandomNumberGenerator(seed: 0xDEF1A7E)
        var inputs: [Data] = []
        for _ in 0 ..< 3000 {
            let count = Int(generator.next() % 64)
            inputs.append(Data((0 ..< count).map { _ in UInt8(truncatingIfNeeded: generator.next()) }))
        }
        let seed = DeflateDecoderTests.dynamic
        for index in seed.indices {
            for flip: UInt8 in [0x01, 0x10, 0x80, 0xFF] {
                var mutated = seed
                mutated[index] ^= flip
                inputs.append(mutated)
            }
        }
        for input in inputs {
            if let output = try? decoder.decode(input) {
                #expect(output.count <= 4096)
            }
        }
    }
}
