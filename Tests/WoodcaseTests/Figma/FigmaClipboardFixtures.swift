//
//  FigmaClipboardFixtures.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The committed clipboard payloads in `Fixtures/Figma` (see its README), and builders for
/// the hand-made containers the hostile tests need.
///
/// The expected versions and chunk lengths were read with Python's `struct` from the
/// committed `clipboard.html` files, not with this reader.
enum FigmaClipboardFixtures {
    /// The cases whose whole `clipboard.html` is committed.
    static let htmlCaseIDs = ["V1", "M1a"]

    /// Each committed payload's fig-kiwi version and compressed chunk lengths.
    static let expectedFraming: [String: (version: UInt32, chunkLengths: [Int])] = [
        "V1": (101, [34989, 1318]),
        "M1a": (101, [34989, 334]),
    ]

    /// The placeholder the curated fixtures carry in place of a file key.
    static let fixtureFileKey = "FixtureFileKey00000000"

    /// One case's committed `clipboard.html`.
    static func html(_ caseID: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: "clipboard", withExtension: "html", subdirectory: "Fixtures/Figma/\(caseID)"
        ))
        return try Data(contentsOf: url)
    }

    /// One case's committed `clipboard.html`, as text.
    static func htmlText(_ caseID: String) throws -> String {
        try #require(String(data: html(caseID), encoding: .utf8))
    }

    /// A container's bytes: `prelude`, the little-endian `version`, then each chunk with
    /// its little-endian length.
    static func container(prelude: String = "fig-kiwi", version: UInt32 = 101, chunks: [Data]) -> Data {
        var data = Data(prelude.utf8)
        data += littleEndian(version)
        for chunk in chunks {
            data += littleEndian(UInt32(chunk.count)) + chunk
        }
        return data
    }

    /// `value`'s four bytes, least significant first.
    static func littleEndian(_ value: UInt32) -> Data {
        Data((0 ..< 4).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) })
    }

    /// A raw deflate stream of one final stored block holding `bytes`.
    static func storedDeflate(_ bytes: Data) -> Data {
        let length = UInt16(bytes.count)
        var data = Data([0x01, UInt8(length & 0xFF), UInt8(length >> 8)])
        data += Data([UInt8(~length & 0xFF), UInt8(~length >> 8)])
        return data + bytes
    }

    /// A zstd frame of one raw block holding `bytes` (fewer than 256), declaring its size
    /// in a one-byte single-segment header and carrying no checksum (RFC 8878 §3.1.1).
    static func rawZstdFrame(_ bytes: Data) -> Data {
        precondition(bytes.count < 256)
        var data = Data([0x28, 0xB5, 0x2F, 0xFD, 0x20, UInt8(bytes.count)])
        let header = UInt32(1) | UInt32(bytes.count) << 3 // last block, raw
        data += Data([UInt8(header & 0xFF), UInt8(header >> 8 & 0xFF), UInt8(header >> 16)])
        return data + bytes
    }

    /// An HTML payload carrying `metadata` and `buffer` the way the desktop app writes it.
    static func html(metadata: Data, buffer: Data) -> Data {
        let text = "<meta charset='utf-8'><span data-metadata=\"<!--(figmeta)"
            + metadata.base64EncodedString() + "(/figmeta)-->\"></span><span data-buffer=\"<!--(figma)"
            + buffer.base64EncodedString() + "(/figma)-->\"></span>"
        return Data(text.utf8)
    }
}
