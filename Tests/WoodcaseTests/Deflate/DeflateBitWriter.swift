//
//  DeflateBitWriter.swift
//  WoodcaseTests
//

import Foundation

/// Writes hand-built deflate streams (RFC 1951), so tests can reach malformed inputs no
/// compressor would emit.
///
/// Header fields are packed least-significant bit first; Huffman codes most-significant
/// bit first, as §3.1.1 says.
struct DeflateBitWriter {
    private var bytes: [UInt8] = []
    private var buffer: UInt32 = 0
    private var count = 0

    /// Appends the low `bits` bits of `value`, least-significant first.
    mutating func write(_ value: UInt32, bits: Int) {
        for bit in 0 ..< bits {
            push((value >> UInt32(bit)) & 1)
        }
    }

    /// Appends a `length`-bit Huffman code, most-significant bit first.
    mutating func writeCode(_ code: UInt32, length: Int) {
        for bit in stride(from: length - 1, through: 0, by: -1) {
            push((code >> UInt32(bit)) & 1)
        }
    }

    /// Appends a block header: the final flag, then the two-bit block type.
    mutating func header(final: Bool, type: UInt32) {
        write(final ? 1 : 0, bits: 1)
        write(type, bits: 2)
    }

    /// Appends `symbol` in the fixed literal/length code (§3.2.6).
    mutating func fixedLiteral(_ symbol: Int) {
        switch symbol {
        case 0 ... 143: writeCode(UInt32(0x30 + symbol), length: 8)
        case 144 ... 255: writeCode(UInt32(0x190 + symbol - 144), length: 9)
        case 256 ... 279: writeCode(UInt32(symbol - 256), length: 7)
        default: writeCode(UInt32(0xC0 + symbol - 280), length: 8)
        }
    }

    /// Appends `symbol` in the fixed distance code: five bits, its own value.
    mutating func fixedDistance(_ symbol: Int) {
        writeCode(UInt32(symbol), length: 5)
    }

    /// The bytes written so far, the last one padded with zero bits.
    var data: Data {
        var result = bytes
        if count > 0 { result.append(UInt8(buffer)) }
        return Data(result)
    }

    private mutating func push(_ bit: UInt32) {
        buffer |= bit << UInt32(count)
        count += 1
        if count == 8 {
            bytes.append(UInt8(buffer))
            buffer = 0
            count = 0
        }
    }
}
