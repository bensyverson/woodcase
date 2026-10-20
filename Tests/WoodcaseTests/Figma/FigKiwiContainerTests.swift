//
//  FigKiwiContainerTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `FigKiwiContainer` frames the fig-kiwi binary: prelude, version and length-prefixed
/// chunks, every length bounded by the bytes that remain.
struct FigKiwiContainerTests {
    private typealias Fixtures = FigmaClipboardFixtures

    @Test("A committed payload reports its version and both chunk lengths", arguments: FigmaClipboardFixtures.htmlCaseIDs)
    func committedFraming(caseID: String) throws {
        let payload = try FigmaClipboardPayload(html: Fixtures.html(caseID))
        let container = try FigKiwiContainer(payload.buffer)
        let expected = try #require(Fixtures.expectedFraming[caseID])
        #expect(container.prelude == .design)
        #expect(container.version == expected.version)
        #expect(container.chunks.map(\.count) == expected.chunkLengths)
    }

    @Test("Each known prelude reads", arguments: FigKiwiContainer.Prelude.allCases)
    func preludes(prelude: FigKiwiContainer.Prelude) throws {
        let data = Fixtures.container(prelude: prelude.rawValue, version: 106, chunks: [Data([1, 2]), Data()])
        let container = try FigKiwiContainer(data)
        #expect(container == FigKiwiContainer(prelude: prelude, version: 106, chunks: [Data([1, 2]), Data()]))
    }

    @Test("A container with no chunks reads as none")
    func noChunks() throws {
        #expect(try FigKiwiContainer(Fixtures.container(chunks: [])).chunks.isEmpty)
    }

    @Test("Chunks keep their bytes when the input is a slice")
    func sliceInput() throws {
        let data = Data([9, 9, 9]) + Fixtures.container(chunks: [Data([7, 8])])
        let container = try FigKiwiContainer(data.dropFirst(3))
        #expect(container.chunks == [Data([7, 8])])
    }

    // MARK: - Refusals

    @Test("An unknown prelude is refused", arguments: ["fig-kiwx", "FIG-KIWI", "zip-kiwi"])
    func unknownPrelude(prelude: String) {
        #expect(throws: FigmaDecodeError.unknownPrelude) {
            try FigKiwiContainer(Fixtures.container(prelude: prelude, chunks: []))
        }
    }

    @Test("Input shorter than the prelude and version is truncated", arguments: [0, 7, 8, 11])
    func truncatedHeader(count: Int) {
        let data = Fixtures.container(chunks: []).prefix(count)
        let expected: FigmaDecodeError = count < 8 ? .unknownPrelude : .truncatedHeader
        #expect(throws: expected) { try FigKiwiContainer(data) }
    }

    @Test("A length field cut short is truncated")
    func truncatedChunkLength() {
        let data = Fixtures.container(chunks: [Data([1])]) + Data([0, 0])
        #expect(throws: FigmaDecodeError.truncatedChunkLength(index: 1)) { try FigKiwiContainer(data) }
    }

    @Test("A chunk longer than the bytes left is refused", arguments: [UInt32(4), 100, .max])
    func chunkTooLong(length: UInt32) {
        let data = Fixtures.container(chunks: []) + Fixtures.littleEndian(length) + Data([1, 2, 3])
        #expect(throws: FigmaDecodeError.chunkExceedsRemainingBytes(index: 0, length: length, remaining: 3)) {
            try FigKiwiContainer(data)
        }
    }

    @Test("A committed payload with its message length enlarged is refused")
    func enlargedCommittedLength() throws {
        var buffer = try FigmaClipboardPayload(html: Fixtures.html("V1")).buffer
        let offset = 12 + 4 + 34989
        buffer.replaceSubrange(offset ..< offset + 4, with: Fixtures.littleEndian(1319))
        #expect(throws: FigmaDecodeError.chunkExceedsRemainingBytes(index: 1, length: 1319, remaining: 1318)) {
            try FigKiwiContainer(buffer)
        }
    }

    @Test("Random and mutated containers never trap")
    func fuzz() {
        var generator = SeededRandomNumberGenerator(seed: 0xF16C1B)
        let seed = Fixtures.container(chunks: [Data([1, 2, 3]), Data([4, 5])])
        for _ in 0 ..< 2000 {
            var mutated = seed
            let index = Int(generator.next() % UInt64(mutated.count))
            mutated[index] = UInt8(truncatingIfNeeded: generator.next())
            let cut = Int(generator.next() % UInt64(mutated.count + 1))
            if let container = try? FigKiwiContainer(mutated.prefix(cut)) {
                #expect(container.chunks.map(\.count).reduce(0, +) <= cut)
            }
        }
    }
}
