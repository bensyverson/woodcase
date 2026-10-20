//
//  FigmaClipboardDecoderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `FigmaClipboardDecoder` takes clipboard HTML to the exact schema and message bytes the
/// curated fixtures hold, and names the step that refused a bad payload.
struct FigmaClipboardDecoderTests {
    private typealias Fixtures = FigmaClipboardFixtures

    /// A container of `chunks`, wrapped in desktop-style HTML.
    private static func html(chunks: [Data]) -> Data {
        Fixtures.html(metadata: Data("{}".utf8), buffer: Fixtures.container(chunks: chunks))
    }

    /// The committed V1 payload's two compressed chunks.
    private static func v1Chunks() throws -> [Data] {
        try FigKiwiContainer(FigmaClipboardPayload(html: Fixtures.html("V1")).buffer).chunks
    }

    @Test("A committed payload decodes to its exact schema and message bytes", arguments: FigmaClipboardFixtures.htmlCaseIDs)
    func committedPayload(caseID: String) throws {
        let clipboard = try FigmaClipboardDecoder().decode(html: Fixtures.html(caseID))
        #expect(try clipboard.schemaData == KiwiFixtures.schemaData())
        #expect(try clipboard.messageData == KiwiFixtures.messageData(caseID))
        #expect(clipboard.schema.definitions.count == 665)
        #expect(clipboard.message.typeName == "Message")
        #expect(clipboard.message["type"]?.enumName == "NODE_CHANGES")
        #expect(clipboard.metadata.fileKey == Fixtures.fixtureFileKey)
        #expect(clipboard.container.chunks.map(\.count) == Fixtures.expectedFraming[caseID]?.chunkLengths)
    }

    @Test("A container with one chunk is missing its message")
    func oneChunk() throws {
        let chunks = try Self.v1Chunks()
        #expect(throws: FigmaDecodeError.missingChunks(found: 1)) {
            try FigmaClipboardDecoder().decode(html: Self.html(chunks: [chunks[0]]))
        }
    }

    @Test("A message chunk without zstd's magic is refused")
    func messageWithoutMagic() throws {
        let chunks = try Self.v1Chunks()
        #expect(throws: FigmaDecodeError.messageDecompression(.notZstd)) {
            try FigmaClipboardDecoder().decode(html: Self.html(chunks: [chunks[0], chunks[0]]))
        }
    }

    @Test("A zstd frame in the schema's place is refused, not inflated to garbage")
    func zstdInSchemaPlace() throws {
        let chunks = try Self.v1Chunks()
        #expect {
            try FigmaClipboardDecoder().decode(html: Self.html(chunks: [chunks[1], chunks[1]]))
        } throws: { error in
            guard case .schemaDecompression = error as? FigmaDecodeError else { return false }
            return true
        }
    }

    @Test("A truncated message chunk is refused")
    func truncatedMessage() throws {
        let chunks = try Self.v1Chunks()
        #expect(throws: FigmaDecodeError.messageDecompression(.truncated)) {
            try FigmaClipboardDecoder().decode(html: Self.html(chunks: [chunks[0], chunks[1].dropLast(5)]))
        }
    }

    @Test("A schema past its cap is refused")
    func schemaCap() throws {
        let decoder = FigmaClipboardDecoder(maxSchemaSize: 1000)
        #expect(throws: FigmaDecodeError.schemaDecompression(.exceedsLimit(limit: 1000))) {
            try decoder.decode(html: Fixtures.html("V1"))
        }
    }

    @Test("A message past its cap is refused")
    func messageCap() throws {
        let decoder = FigmaClipboardDecoder(maxMessageSize: 100)
        #expect(throws: FigmaDecodeError.messageDecompression(.exceedsLimit(limit: 100))) {
            try decoder.decode(html: Fixtures.html("V1"))
        }
    }

    @Test("Inflated bytes that are not a Kiwi schema are refused")
    func notASchema() throws {
        let chunks = try Self.v1Chunks()
        let schema = Fixtures.storedDeflate(Data([0xFF, 0xFF, 0xFF]))
        #expect {
            try FigmaClipboardDecoder().decode(html: Self.html(chunks: [schema, chunks[1]]))
        } throws: { error in
            guard case .schemaDecoding = error as? FigmaDecodeError else { return false }
            return true
        }
    }

    @Test("A message that does not decode as Message is refused")
    func notAMessage() throws {
        let chunks = try Self.v1Chunks()
        let message = Fixtures.rawZstdFrame(Data([0x7F]))
        #expect {
            try FigmaClipboardDecoder().decode(html: Self.html(chunks: [chunks[0], message]))
        } throws: { error in
            guard case .messageDecoding = error as? FigmaDecodeError else { return false }
            return true
        }
    }

    @Test("A stored block whose complement disagrees still ends in a typed error")
    func storedComplementMismatch() throws {
        // Apple's inflate does not check the complement, so the Kiwi step must refuse it.
        let chunks = try Self.v1Chunks()
        let schema = Data([0x01, 0x03, 0x00, 0x00, 0x00, 0xFF, 0xFF, 0xFF])
        #expect(throws: FigmaDecodeError.self) {
            try FigmaClipboardDecoder().decode(html: Self.html(chunks: [schema, chunks[1]]))
        }
    }

    @Test("Corrupted schema chunks end in a typed error or a schema, never a trap")
    func corruptedSchemaChunks() throws {
        // Deflate has no checksum, so this cannot demand an error: a flip inside a literal
        // can rename a definition, and Kiwi messages carry field ids, not names, so the
        // message still decodes. Measured 2026-10-20 over every 37th byte of V1's chunk 0,
        // two flips each: 476 of 1,892 corruptions decoded, to a different schema. The
        // sample here is sparser to keep the suite fast.
        let chunks = try Self.v1Chunks()
        let decoder = FigmaClipboardDecoder()
        for index in stride(from: 0, to: chunks[0].count, by: 1999) {
            for flip: UInt8 in [0x01, 0x40] {
                var corrupted = chunks[0]
                corrupted[corrupted.startIndex + index] ^= flip
                if let clipboard = try? decoder.decode(html: Self.html(chunks: [corrupted, chunks[1]])) {
                    #expect(clipboard.message.typeName == FigmaClipboardDecoder.rootType)
                }
            }
        }
    }

    @Test("Bytes after the schema's final block do not change the schema")
    func schemaTrailingBytes() throws {
        // Apple's inflate consumes them silently; the container already bounds the chunk.
        let chunks = try Self.v1Chunks()
        let clipboard = try FigmaClipboardDecoder().decode(html: Self.html(chunks: [chunks[0] + Data([0, 0]), chunks[1]]))
        #expect(try clipboard.schemaData == KiwiFixtures.schemaData())
    }

    @Test("Chunks after the message are ignored")
    func extraChunks() throws {
        let chunks = try Self.v1Chunks()
        let clipboard = try FigmaClipboardDecoder().decode(html: Self.html(chunks: chunks + [Data([1, 2, 3])]))
        #expect(try clipboard.messageData == KiwiFixtures.messageData("V1"))
        #expect(clipboard.container.chunks.count == 3)
    }
}
