//
//  PropertyWriteFallbackTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The single-key write on payloads the fixtures do not have: one it cannot follow is
/// written whole, exactly as before, and one it can follow refuses a bad value with what
/// the whole write refused it with.
struct PropertyWriteFallbackTests {
    /// A payload that writes and reads one key through a nested container — a route the
    /// overlay does not follow.
    private struct NestedPayload: Codable, Equatable {
        enum Key: String, CodingKey { case inner, plain }
        enum InnerKey: String, CodingKey { case value }

        var plain: Int
        var inner: String

        init(plain: Int, inner: String) {
            self.plain = plain
            self.inner = inner
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            plain = try container.decode(Int.self, forKey: .plain)
            inner = try container.nestedContainer(keyedBy: InnerKey.self, forKey: .inner)
                .decode(String.self, forKey: .value)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(plain, forKey: .plain)
            var inner = container.nestedContainer(keyedBy: InnerKey.self, forKey: .inner)
            try inner.encode(self.inner, forKey: .value)
        }
    }

    /// A payload that reads a key back as a different type than it writes it, so the
    /// captured value cannot be handed back as it is.
    private struct WidenedPayload: Codable, Equatable {
        enum Key: String, CodingKey { case count, label }

        var count: Int
        var label: String?

        init(count: Int, label: String?) {
            self.count = count
            self.label = label
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: Key.self)
            count = try container.decode(Int.self, forKey: .count)
            label = try container.decodeIfPresent(String.self, forKey: .label)
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(Int32(count), forKey: .count)
            try container.encodeIfPresent(label, forKey: .label)
        }
    }

    /// A payload shaped like the node payloads: synthesized, flat, mostly optional.
    private struct PlainPayload: Codable, Equatable {
        var count: Int
        var label: String?
        var tags: [String]?
        var counts: [Int]?
    }

    /// The old write of one key of a payload: the whole dictionary, round-tripped.
    private static func wholeWrite<P: Codable>(_ payload: P, field: String, value: AnyCodable) throws -> P {
        try NodePropertyCodec.decode(
            P.self,
            from: NodePropertyCodec.patching(NodePropertyCodec.dictionary(from: payload), field: field, value: value)
        )
    }

    /// Runs `body` with a fresh counter installed and returns the counter.
    private static func counting(_ body: () throws -> Void) rethrows -> PropertyCostCounter {
        let counter = PropertyCostCounter()
        try PropertyCostCounter.$current.withValue(counter) { try body() }
        return counter
    }

    @Test("A payload written through a nested container is written whole, the same as before")
    func nestedPayloadFallsBack() throws {
        let nested = NestedPayload(plain: 7, inner: "deep")
        let inner = AnyCodable.dictionary(["value": .string("x")])
        #expect(try NodePropertyCodec.overlaying(nested, key: "plain", value: .int(8)) == nil)
        #expect(try NodePropertyCodec.overlaying(nested, key: "inner", value: inner) == nil)
        for (field, value) in [("plain", AnyCodable.int(8)), ("inner", inner)] {
            #expect(try NodePropertyCodec.patchingPayload(nested, field: field, value: value)
                == Self.wholeWrite(nested, field: field, value: value))
        }
    }

    @Test("A payload that is not an object is written whole, the same as before")
    func singleValuePayloadFallsBack() throws {
        // `AnyCodable` encodes through a single-value container.
        let object = AnyCodable.dictionary(["x": .int(1)])
        #expect(try NodePropertyCodec.overlaying(object, key: "x", value: .int(2)) == nil)
        #expect(try NodePropertyCodec.patchingPayload(object, field: "x", value: .int(2)) == .dictionary(["x": .int(2)]))
    }

    @Test("A key read back as another type than it was written makes the write whole")
    func widenedKeyFallsBack() throws {
        let payload = WidenedPayload(count: 3, label: "a")
        #expect(try NodePropertyCodec.overlaying(payload, key: "label", value: .string("b")) == nil)
        var patched = payload
        let counter = try Self.counting {
            patched = try NodePropertyCodec.patchingPayload(payload, field: "label", value: .string("b"))
        }
        #expect(patched == WidenedPayload(count: 3, label: "b"))
        #expect(counter.count(of: .payloadEncode) == 1)
        #expect(counter.count(of: .payloadDecode) == 1)
    }

    @Test("A flat payload is written key by key, and a clear removes the key")
    func plainPayloadIsOverlaid() throws {
        let payload = PlainPayload(count: 3, label: "a", tags: ["x"], counts: nil)
        var written: [PlainPayload?] = []
        let counter = try Self.counting {
            try written.append(NodePropertyCodec.overlaying(payload, key: "label", value: .string("b")))
            try written.append(NodePropertyCodec.overlaying(payload, key: "tags", value: .null))
            try written.append(NodePropertyCodec.overlaying(payload, key: "count", value: .double(4)))
        }
        #expect(written == [
            PlainPayload(count: 3, label: "b", tags: ["x"], counts: nil),
            PlainPayload(count: 3, label: "a", tags: nil, counts: nil),
            PlainPayload(count: 4, label: "a", tags: ["x"], counts: nil),
        ])
        #expect(counter.count(of: .payloadEncode) == 0)
        #expect(counter.count(of: .payloadDecode) == 0)
    }

    @Test("A value the payload refuses throws what the whole write threw", arguments: [
        ("count", AnyCodable.string("three")), ("count", .null), ("count", .double(1.5)),
        ("label", .int(4)), ("tags", .array([.int(1)])), ("tags", .dictionary(["a": .string("b")])),
        ("counts", .array([.int(1), .string("2")])),
    ])
    func refusalsMatch(field: String, value: AnyCodable) {
        let payload = PlainPayload(count: 3, label: "a", tags: ["x"], counts: nil)
        let old = Result(catching: { try Self.wholeWrite(payload, field: field, value: value) })
        let new = Result(catching: { try NodePropertyCodec.patchingPayload(payload, field: field, value: value) })
        guard case let .failure(oldError) = old, case let .failure(newError) = new else {
            Issue.record("\(field) = \(value) did not refuse both ways: \(old) vs \(new)")
            return
        }
        // The refusal a caller sees: the clause inside it is shown for structured values only.
        let expected = NodePropertyCodec.mismatch("kind.\(field)", field, value, "n", oldError)
        #expect(NodePropertyCodec.mismatch("kind.\(field)", field, value, "n", newError) == expected)
    }

    /// The one refusal that reads differently, and better: `JSONDecoder` reports a
    /// fractional number where an integer belongs, inside an array or object, as "The given
    /// data was not valid JSON."; the overlay decodes the new value with
    /// ``AnyCodableDecoder``, which points at the element. A mesh fill's `columns: 1.5`
    /// is the case a .pen file can hit.
    @Test("A fractional number where an integer belongs is refused at its place")
    func fractionalIntegerIsLocated() {
        let payload = PlainPayload(count: 3, label: nil, tags: nil, counts: nil)
        let value = AnyCodable.array([.int(1), .double(1.5)])
        let old = Result(catching: { try Self.wholeWrite(payload, field: "counts", value: value) })
        let new = Result(catching: { try NodePropertyCodec.patchingPayload(payload, field: "counts", value: value) })
        guard case let .failure(oldError) = old, case let .failure(newError) = new else {
            Issue.record("did not refuse both ways: \(old) vs \(new)")
            return
        }
        #expect(PenDecodingFailure.clause(for: oldError, field: "counts") == "The given data was not valid JSON.")
        #expect(PenDecodingFailure.clause(for: newError, field: "counts")
            == "[1]: the value there is not one of the accepted forms")
    }
}
