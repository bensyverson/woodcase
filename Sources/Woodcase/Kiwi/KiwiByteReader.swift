//
//  KiwiByteReader.swift
//  Woodcase
//

import Foundation

/// A cursor over Kiwi-encoded bytes that reads one primitive at a time.
///
/// Each read either returns a value and advances, or throws a ``KiwiDecodingError``
/// without reading past the end. Lengths and counts are checked against the bytes that
/// remain before anything is allocated for them.
public struct KiwiByteReader: Friendly {
    /// The bytes being read.
    public let bytes: [UInt8]
    /// The offset of the next byte to read.
    public private(set) var offset: Int = 0

    /// A reader positioned at the first byte of `data`.
    public init(_ data: Data) {
        bytes = [UInt8](data)
    }

    /// The number of bytes not yet read.
    public var remainingCount: Int {
        bytes.count - offset
    }

    /// Whether every byte has been read.
    public var isAtEnd: Bool {
        offset == bytes.count
    }

    /// Reads one raw byte.
    public mutating func readByte() throws(KiwiDecodingError) -> UInt8 {
        guard offset < bytes.count else { throw .truncated(offset: offset) }
        defer { offset += 1 }
        return bytes[offset]
    }

    /// Reads a bool: one byte, true when it is not zero.
    public mutating func readBool() throws(KiwiDecodingError) -> Bool {
        try readByte() != 0
    }

    /// Reads an unsigned LEB128 varint of at most five bytes.
    ///
    /// Bits past the 32nd in the fifth byte are dropped, as Kiwi's own reader drops them;
    /// a fifth byte that still has its continuation bit set is malformed.
    public mutating func readVarUInt() throws(KiwiDecodingError) -> UInt32 {
        let start = offset
        var value: UInt64 = 0
        for index in 0 ..< 5 {
            guard offset < bytes.count else { throw .truncated(offset: start) }
            let byte = bytes[offset]
            offset += 1
            value |= UInt64(byte & 0x7F) << (7 * UInt64(index))
            if byte & 0x80 == 0 { return UInt32(truncatingIfNeeded: value) }
        }
        offset = start
        throw .malformedVarint(offset: start)
    }

    /// Reads a zigzag-encoded signed varint.
    public mutating func readVarInt() throws(KiwiDecodingError) -> Int32 {
        let raw = try readVarUInt()
        return Int32(bitPattern: (raw >> 1) ^ (0 &- (raw & 1)))
    }

    /// Reads an unsigned varint of at most nine bytes, the ninth contributing all eight
    /// of its bits.
    public mutating func readVarUInt64() throws(KiwiDecodingError) -> UInt64 {
        let start = offset
        var value: UInt64 = 0
        for index in 0 ..< 9 {
            guard offset < bytes.count else { throw .truncated(offset: start) }
            let byte = bytes[offset]
            offset += 1
            if index == 8 {
                return value | UInt64(byte) << 56
            }
            value |= UInt64(byte & 0x7F) << (7 * UInt64(index))
            if byte & 0x80 == 0 { return value }
        }
        return value
    }

    /// Reads a zigzag-encoded 64-bit signed varint.
    public mutating func readVarInt64() throws(KiwiDecodingError) -> Int64 {
        let raw = try readVarUInt64()
        return Int64(bitPattern: (raw >> 1) ^ (0 &- (raw & 1)))
    }

    /// Reads a Kiwi float: a single zero byte for zero, otherwise four little-endian bytes
    /// holding the IEEE bits rotated left by nine, so the exponent comes first.
    public mutating func readVarFloat() throws(KiwiDecodingError) -> Float {
        let start = offset
        guard offset < bytes.count else { throw .truncated(offset: start) }
        if bytes[offset] == 0 {
            offset += 1
            return 0
        }
        guard remainingCount >= 4 else { throw .truncated(offset: start) }
        let rotated = UInt32(bytes[offset])
            | UInt32(bytes[offset + 1]) << 8
            | UInt32(bytes[offset + 2]) << 16
            | UInt32(bytes[offset + 3]) << 24
        offset += 4
        return Float(bitPattern: rotated << 23 | rotated >> 9)
    }

    /// Reads a null-terminated UTF-8 string.
    ///
    /// Invalid UTF-8 decodes with replacement characters rather than failing, so text
    /// written by a lenient encoder still reads.
    public mutating func readString() throws(KiwiDecodingError) -> String {
        let start = offset
        guard let end = bytes[offset...].firstIndex(of: 0) else { throw .truncated(offset: start) }
        offset = end + 1
        return String(decoding: bytes[start ..< end], as: UTF8.self)
    }

    /// Reads a varint count and checks that at least that many bytes remain after it.
    ///
    /// Every encoded element of a Kiwi array takes at least one byte except a struct
    /// without fields, so this bounds what a count can make a decoder allocate or loop.
    public mutating func readCount() throws(KiwiDecodingError) -> Int {
        let start = offset
        let count = try readVarUInt()
        guard Int(count) <= remainingCount else {
            offset = start
            throw .countExceedsRemainingBytes(count: count, offset: start)
        }
        return Int(count)
    }

    /// Reads a length-prefixed byte array.
    public mutating func readByteArray() throws(KiwiDecodingError) -> Data {
        let count = try readCount()
        defer { offset += count }
        return Data(bytes[offset ..< offset + count])
    }
}
