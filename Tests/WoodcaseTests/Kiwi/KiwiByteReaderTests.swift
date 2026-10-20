//
//  KiwiByteReaderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `KiwiByteReader` reads Kiwi's primitive encodings and fails with a typed error at the
/// first byte it cannot trust.
///
/// Expected values are worked by hand from the Kiwi encoding: LEB128 varints, zigzag for
/// signed values, null-terminated strings, and the float encoding that rotates the IEEE
/// bits left by nine so the exponent leads.
struct KiwiByteReaderTests {
    private static func reader(_ bytes: UInt8...) -> KiwiByteReader {
        KiwiByteReader(Data(bytes))
    }

    // MARK: - Varints

    @Test(arguments: [
        ([0x00], 0),
        ([0x7F], 127),
        ([0x80, 0x01], 128),
        ([0x99, 0x05], 665),
        ([0xFF, 0xFF, 0xFF, 0xFF, 0x0F], UInt32.max),
    ] as [([UInt8], UInt32)])
    func readsUnsignedVarints(bytes: [UInt8], expected: UInt32) throws {
        var reader = KiwiByteReader(Data(bytes))
        #expect(try reader.readVarUInt() == expected)
        #expect(reader.isAtEnd)
    }

    @Test func readsZigzagSignedVarints() throws {
        var reader = Self.reader(0x00, 0x01, 0x02, 0xFE, 0xAB, 0xB2, 0xD1, 0x0A)
        #expect(try reader.readVarInt() == 0)
        #expect(try reader.readVarInt() == -1)
        #expect(try reader.readVarInt() == 1)
        #expect(try reader.readVarInt() == 1_427_524_351)
    }

    @Test func rejectsAVarintLongerThanFiveBytes() {
        var reader = Self.reader(0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0x01)
        #expect(throws: KiwiDecodingError.malformedVarint(offset: 0)) { try reader.readVarUInt() }
    }

    @Test func reportsATruncatedVarint() {
        var reader = Self.reader(0x80, 0x80)
        #expect(throws: KiwiDecodingError.truncated(offset: 0)) { try reader.readVarUInt() }
    }

    @Test func readsSixtyFourBitVarints() throws {
        var reader = Self.reader(
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
            0xAC, 0x02,
            0x01,
            0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF
        )
        #expect(try reader.readVarUInt64() == UInt64.max)
        #expect(try reader.readVarUInt64() == 300)
        #expect(try reader.readVarInt64() == -1)
        #expect(try reader.readVarInt64() == Int64.min)
        #expect(reader.isAtEnd)
    }

    // MARK: - Floats

    @Test(arguments: [
        ([0x00], 0),
        ([0x7F, 0x00, 0x00, 0x00], 1),
        ([0x88, 0x00, 0x00, 0x18], 560),
        ([0x80, 0x01, 0x00, 0x40], -2.5),
    ] as [([UInt8], Float)])
    func readsFloats(bytes: [UInt8], expected: Float) throws {
        var reader = KiwiByteReader(Data(bytes))
        #expect(try reader.readVarFloat() == expected)
        #expect(reader.isAtEnd)
    }

    @Test func reportsATruncatedFloat() {
        var reader = Self.reader(0x88, 0x00)
        #expect(throws: KiwiDecodingError.truncated(offset: 0)) { try reader.readVarFloat() }
    }

    // MARK: - Strings, bytes and counts

    @Test func readsNullTerminatedStrings() throws {
        var reader = Self.reader(0x68, 0x69, 0x00, 0x00, 0xC3, 0xA9, 0x00)
        #expect(try reader.readString() == "hi")
        #expect(try reader.readString() == "")
        #expect(try reader.readString() == "é")
        #expect(reader.isAtEnd)
    }

    @Test func reportsAnUnterminatedString() {
        var reader = Self.reader(0x68, 0x69)
        #expect(throws: KiwiDecodingError.truncated(offset: 0)) { try reader.readString() }
    }

    @Test func readsByteArrays() throws {
        var reader = Self.reader(0x03, 0x0A, 0x0B, 0x0C, 0x00)
        #expect(try reader.readByteArray() == Data([0x0A, 0x0B, 0x0C]))
        #expect(try reader.readByteArray() == Data())
        #expect(reader.isAtEnd)
    }

    @Test func refusesAByteArrayLongerThanTheInput() {
        var reader = Self.reader(0x05, 0x0A)
        #expect(throws: KiwiDecodingError.countExceedsRemainingBytes(count: 5, offset: 0)) {
            try reader.readByteArray()
        }
    }

    @Test func refusesACountLargerThanTheRemainingBytes() {
        var reader = Self.reader(0xFF, 0xFF, 0xFF, 0xFF, 0x0F, 0x00)
        #expect(throws: KiwiDecodingError.countExceedsRemainingBytes(count: UInt32.max, offset: 0)) {
            try reader.readCount()
        }
    }

    @Test func readsBoolsAndBytes() throws {
        var reader = Self.reader(0x00, 0x01, 0x07, 0xAB)
        #expect(try reader.readBool() == false)
        #expect(try reader.readBool() == true)
        #expect(try reader.readBool() == true)
        #expect(try reader.readByte() == 0xAB)
        #expect(throws: KiwiDecodingError.truncated(offset: 4)) { try reader.readByte() }
    }

    @Test func tracksItsOffset() throws {
        var reader = Self.reader(0x80, 0x01, 0x00)
        _ = try reader.readVarUInt()
        #expect(reader.offset == 2)
        #expect(reader.remainingCount == 1)
        #expect(!reader.isAtEnd)
    }
}
