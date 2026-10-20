//
//  FigmaBlobReader.swift
//  Woodcase
//

import Foundation

/// A cursor over a Figma blob's fixed-width little-endian fields.
///
/// Blobs are not Kiwi-encoded: counts and indices are plain `UInt32`s and coordinates
/// plain IEEE 754 singles, so this is separate from ``KiwiByteReader``. Every read checks
/// the bytes that remain and throws rather than reading past the end.
struct FigmaBlobReader {
    /// The blob's bytes.
    let bytes: [UInt8]
    /// The offset of the next byte to read.
    private(set) var offset = 0

    /// A reader at the first byte of `data`.
    init(_ data: Data) {
        bytes = [UInt8](data)
    }

    /// The bytes not yet read.
    var remainingCount: Int {
        bytes.count - offset
    }

    /// Whether every byte has been read.
    var isAtEnd: Bool {
        offset == bytes.count
    }

    /// Reads one byte.
    mutating func readByte() throws(FigmaBlobError) -> UInt8 {
        guard offset < bytes.count else { throw .truncated(offset: offset) }
        defer { offset += 1 }
        return bytes[offset]
    }

    /// Reads a little-endian `UInt32`.
    mutating func readUInt32() throws(FigmaBlobError) -> UInt32 {
        guard remainingCount >= 4 else { throw .truncated(offset: offset) }
        defer { offset += 4 }
        return (0 ..< 4).reduce(UInt32(0)) { $0 | UInt32(bytes[offset + $1]) << (8 * UInt32($1)) }
    }

    /// Reads a little-endian `UInt32` that indexes something, as an `Int`.
    mutating func readIndex() throws(FigmaBlobError) -> Int {
        try Int(readUInt32())
    }

    /// Reads a count of items `stride` bytes each, refusing one that cannot fit in the
    /// bytes that remain, so nothing is allocated for it first.
    mutating func readCount(stride: Int) throws(FigmaBlobError) -> Int {
        let start = offset
        let count = try readUInt32()
        guard Int(count) <= remainingCount / stride else {
            throw .countExceedsRemainingBytes(count: count, offset: start)
        }
        return Int(count)
    }

    /// Reads a little-endian single and widens it, refusing a NaN or an infinity.
    mutating func readFloat() throws(FigmaBlobError) -> Double {
        let start = offset
        let value = try Float(bitPattern: readUInt32())
        guard value.isFinite else { throw .nonFiniteValue(offset: start) }
        return Double(value)
    }

    /// Reads two singles as a point.
    mutating func readPoint() throws(FigmaBlobError) -> FigmaPoint {
        let x = try readFloat()
        return try FigmaPoint(x: x, y: readFloat())
    }
}
