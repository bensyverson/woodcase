//
//  ZstdDecoderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `ZstdDecoder` turns one zstd frame into its exact bytes, or a typed error — never
/// garbage, and never more than its cap.
///
/// The frames in `Fixtures/zstd` come from `scripts/gen-zstd-fixtures`: `sample.txt`
/// compressed from a file (content size in the header) and from a pipe (no content size),
/// and the 64 KiB `i % 251` pattern the same two ways.
struct ZstdDecoderTests {
    // MARK: - Fixtures

    private static let roomy = ZstdDecoder(maxDecodedSize: 1 << 20)
    private static let small = ZstdDecoder(maxDecodedSize: 1024)

    private static func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: ext, subdirectory: "Fixtures/zstd"
        ))
        return try Data(contentsOf: url)
    }

    /// The bytes `pattern.zst` and `pattern-unknown-size.zst` hold.
    private static let pattern = Data((0 ..< 65536).map { UInt8($0 % 251) })

    private static func expectError(
        _ expected: ZstdDecodeError,
        decoding frame: Data,
        with decoder: ZstdDecoder = roomy
    ) {
        #expect(throws: expected) { try decoder.decode(frame) }
    }

    // MARK: - Decoding

    @Test("A frame with its content size declared decodes to its exact bytes")
    func declaredSize() throws {
        let decoded = try Self.roomy.decode(Self.fixture("sample", "zst"))
        #expect(try decoded == Self.fixture("sample", "txt"))
    }

    @Test("A frame without a declared content size decodes to its exact bytes")
    func unknownSize() throws {
        let decoded = try Self.roomy.decode(Self.fixture("sample-unknown-size", "zst"))
        #expect(try decoded == Self.fixture("sample", "txt"))
    }

    @Test("A 64 KiB frame decodes to its exact bytes, with and without a declared size", arguments: [
        "pattern", "pattern-unknown-size",
    ])
    func largerFrame(name: String) throws {
        #expect(try Self.roomy.decode(Self.fixture(name, "zst")) == Self.pattern)
    }

    @Test("A cap equal to the decoded size admits the frame", arguments: [
        "pattern", "pattern-unknown-size",
    ])
    func capAtExactSize(name: String) throws {
        let decoder = ZstdDecoder(maxDecodedSize: Self.pattern.count)
        #expect(try decoder.decode(Self.fixture(name, "zst")) == Self.pattern)
    }

    // MARK: - The cap

    @Test("A declared content size over the cap is refused from the header")
    func declaredOverCap() throws {
        try Self.expectError(
            .exceedsLimit(limit: 1024), decoding: Self.fixture("pattern", "zst"), with: Self.small
        )
    }

    @Test("A stream without a declared size is stopped once it passes the cap")
    func streamedOverCap() throws {
        try Self.expectError(
            .exceedsLimit(limit: 1024),
            decoding: Self.fixture("pattern-unknown-size", "zst"),
            with: Self.small
        )
    }

    @Test("A cap one byte short of the decoded size refuses the frame", arguments: [
        "pattern", "pattern-unknown-size",
    ])
    func capOneShort(name: String) throws {
        let decoder = ZstdDecoder(maxDecodedSize: Self.pattern.count - 1)
        try Self.expectError(
            .exceedsLimit(limit: Self.pattern.count - 1),
            decoding: Self.fixture(name, "zst"),
            with: decoder
        )
    }

    @Test("A stream whose window is larger than a small cap allows is refused")
    func windowOverCap() throws {
        try Self.expectError(
            .exceedsLimit(limit: 1024),
            decoding: Self.fixture("sample-window-16mib", "zst"),
            with: Self.small
        )
    }

    @Test("A stream whose window a larger cap allows decodes to its exact bytes")
    func windowUnderCap() throws {
        let decoder = ZstdDecoder(maxDecodedSize: 32 << 20)
        let decoded = try decoder.decode(Self.fixture("sample-window-16mib", "zst"))
        #expect(try decoded == Self.fixture("sample", "txt"))
    }

    @Test("The stream window limit follows the cap within 8 MiB and 128 MiB", arguments: [
        (0, 23), (1024, 23), (8 << 20, 23), ((8 << 20) + 1, 24), (32 << 20, 25),
        (128 << 20, 27), (1 << 30, 27),
    ])
    func windowLimit(cap: Int, log: Int) {
        #expect(ZstdDecoder(maxDecodedSize: cap).windowLogMax == log)
    }

    // MARK: - Wrong format

    @Test("Empty input is not a zstd frame")
    func empty() {
        Self.expectError(.notZstd, decoding: Data())
    }

    @Test("Input shorter than the magic number is not a zstd frame")
    func shorterThanMagic() {
        Self.expectError(.notZstd, decoding: Data([0x28, 0xB5, 0x2F]))
    }

    @Test("A zlib stream is not a zstd frame")
    func zlib() {
        // `printf 'hello' | python3 -c 'import sys,zlib;sys.stdout.buffer.write(zlib.compress(sys.stdin.buffer.read()))'`
        let zlib = Data([
            0x78, 0x9C, 0xCB, 0x48, 0xCD, 0xC9, 0xC9, 0x07, 0x00, 0x06, 0x2C, 0x02, 0x15,
        ])
        Self.expectError(.notZstd, decoding: zlib)
    }

    @Test("A fig-kiwi container is not a zstd frame")
    func figKiwi() {
        Self.expectError(.notZstd, decoding: Data("fig-kiwi\u{0}\u{0}\u{0}\u{0}".utf8))
    }

    @Test("A skippable frame is not a zstd frame")
    func skippable() {
        Self.expectError(.notZstd, decoding: Data([0x50, 0x2A, 0x4D, 0x18, 0, 0, 0, 0]))
    }

    // MARK: - Damaged frames

    @Test("A frame cut short inside its header is truncated")
    func truncatedHeader() throws {
        let frame = try Self.fixture("sample", "zst")
        Self.expectError(.truncated, decoding: frame.prefix(5))
    }

    @Test("A frame cut short inside its blocks is truncated", arguments: [
        "sample", "sample-unknown-size",
    ])
    func truncatedBody(name: String) throws {
        let frame = try Self.fixture(name, "zst")
        Self.expectError(.truncated, decoding: frame.dropLast(10))
    }

    @Test("A frame whose checksum does not match its content is corrupt")
    func checksumMismatch() throws {
        var frame = try Self.fixture("sample", "zst")
        frame[frame.endIndex - 1] ^= 0xFF
        #expect {
            try Self.roomy.decode(frame)
        } throws: { error in
            guard case .corrupt = error as? ZstdDecodeError else { return false }
            return true
        }
    }

    @Test("Bytes after the frame are refused rather than ignored")
    func trailingBytes() throws {
        let frame = try Self.fixture("sample", "zst") + Data([1, 2, 3])
        Self.expectError(.trailingBytes(count: 3), decoding: frame)
    }
}
