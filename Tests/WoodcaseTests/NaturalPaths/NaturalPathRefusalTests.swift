//
//  NaturalPathRefusalTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Rule 3: writing a Woodcase-owned key at its storage path is refused, with an error that
/// names the natural path, so there is one way in and two spellings cannot drift apart.
/// Reading the raw metadata still shows what is stored.
@MainActor
struct NaturalPathRefusalTests {
    private typealias Fixture = NaturalPathFixture

    private func refusal(_ intent: EditIntent, at address: String) throws -> EditRefusal? {
        try PlannerFixture.refusal(intent, at: address, in: Fixture.document())
    }

    @Test("A set at a storage path is refused, naming the natural path",
          arguments: [
              ("common.metadata.woodcase.strokeDash", "kind.strokeDash", AnyCodable.array([4, 2])),
              ("common.metadata.woodcase.strokeDashOffset", "kind.strokeDashOffset", AnyCodable.int(1)),
              ("common.metadata.woodcase.strokeMiterLimit", "kind.strokeMiterLimit", AnyCodable.int(6)),
              ("common.metadata.woodcase.locked", "common.locked", AnyCodable.bool(true)),
              ("common.metadata.woodcase.blendMode", "kind.blendMode", AnyCodable.string("screen")),
          ])
    func storagePathRefused(storage: String, natural: String, value: AnyCodable) throws {
        let refusal = try #require(try refusal(.set([storage: value]), at: "Board/Plain"))
        #expect(refusal.code == .storedAtNaturalPath)
        #expect(refusal.property == storage)
        #expect(refusal.message.contains(natural), "\(refusal.message)")
        #expect(refusal.suggestion?.contains("\(natural)=") == true, "\(String(describing: refusal.suggestion))")
    }

    @Test("A text's spans and default mark at their storage paths are refused too")
    func textStoragePathsRefused() throws {
        let spans = try #require(try refusal(.set(["common.metadata.woodcase.spans": .null]), at: "Board/Label"))
        #expect(spans.code == .storedAtNaturalPath)
        #expect(spans.message.contains("kind.spans"))
        let mark = try #require(try refusal(.set(["common.metadata.woodcase.defaultTextStyle": true]), at: "Board/Label"))
        #expect(mark.message.contains("kind.defaultTextStyle"))
    }

    @Test("A deep key below a storage path is refused the same way")
    func deeperRefused() throws {
        let refusal = try #require(try refusal(.set(["common.metadata.woodcase.spans.text": "Hi"]), at: "Board/Label"))
        #expect(refusal.code == .storedAtNaturalPath)
        #expect(refusal.message.contains("kind.spans"))
    }

    @Test("The EditingError says what happened and what to write")
    func errorTeaches() throws {
        let error = EditingError.storedAtNaturalPath(
            nodeID: "Crd01", path: "common.metadata.woodcase.strokeDash", naturalPath: "kind.strokeDash"
        )
        #expect(error.code == "storedAtNaturalPath")
        let message = try BatchErrorMessage.describe(error, in: Fixture.document(), dialect: .command(file: "design.pen"))
        #expect(message.contains("common.metadata.woodcase.strokeDash is stored for you; write kind.strokeDash"), "\(message)")
    }

    /// A code-generation key has a natural path since tRzkPS (codegen.role), so it left this test.
    @Test("Keys with no natural path are still written at their storage path")
    func otherKeysStillWrite() throws {
        #expect(try refusal(.set(["common.metadata.woodcase.tint": "#A5D6A7"]), at: "Board/Plain") == nil)
    }

    @Test("The whole metadata object is still written as it is given")
    func wholeMetadataWrites() throws {
        let metadata: AnyCodable = ["type": "woodcase", "woodcase": ["strokeDash": [4, 2]]]
        let document = try Fixture.document()
        let plan = try EditPlanner.plan(.set(["common.metadata": metadata]), routedAt: .node(id: "Pln01"), in: document)
        try Fixture.apply(plan, to: document)
        #expect(document.node(id: "Pln01")?.strokeDash?.lengths == [4, 2])
    }

    @Test("Reading a storage path still shows what is stored")
    func rawReadStillWorks() throws {
        let card = try Fixture.node("Crd01")
        #expect(try NodePropertyCodec.value(at: "common.metadata.woodcase.strokeDash", of: card) == [8, 4])
        guard case let .dictionary(metadata) = try NodePropertyCodec.value(at: "common.metadata", of: card),
              case let .dictionary(keys)? = metadata["woodcase"]
        else {
            Issue.record("common.metadata did not read the namespace")
            return
        }
        #expect(keys["locked"] == true)
    }

    @Test("An override at a storage path is refused, naming the natural path")
    func overrideStoragePathRefused() throws {
        let refusal = try #require(try refusal(
            .override(["common.metadata.woodcase.strokeDash": [4, 2]]), at: "Board/Inst/Box"
        ))
        #expect(refusal.code == .storedAtNaturalPath)
        #expect(refusal.message.contains("kind.strokeDash"))
    }
}
