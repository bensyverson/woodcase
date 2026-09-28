//
//  AnyCodableDecoderTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Holds ``AnyCodableDecoder`` to `JSONDecoder` reading the same value written out by
/// `JSONEncoder` — the round trip it replaces in ``PenNodePatcher``.
///
/// Each case decodes one value as one type both ways and requires the same answer:
/// equal results, or both refused.
struct AnyCodableDecoderTests {
    /// The values every type is tried against: each JSON shape, and the numbers whose
    /// crossing between `Int` and `Double` the round trip decides.
    static let values: [AnyCodable] = [
        .null, .bool(true), .bool(false), .int(0), .int(1), .int(-7), .int(300), .int(Int.max),
        .double(3.0), .double(-0.0), .double(2.5), .double(1e20), .double(0.1), .double(1e300),
        .string("x"), .string("$spacing.large"), .string("fit_content(40)"), .string("#ff0000"),
        .array([]), .array([.int(1), .double(2.5)]), .array([.null]),
        .dictionary([:]), .dictionary(["a": .double(4.0), "b": .null]),
        .dictionary(["type": .string("solid"), "color": .string("#fff")]),
        .dictionary(["type": .string("text"), "id": .string("t1"), "content": .string("Hi"), "extra": .double(2.0)]),
        .dictionary(["type": .string("frame"), "id": .string("f1"), "children": .array([
            .dictionary(["type": .string("rectangle"), "id": .string("r1"), "width": .int(10)]),
        ])]),
    ]

    /// Decodes `value` as `T` both ways and compares.
    private func agree<T: Decodable & Equatable>(_: T.Type, _ value: AnyCodable) throws {
        let data = try JSONEncoder().encode(value)
        let viaJSON = try? JSONDecoder().decode(T.self, from: data)
        let inMemory = try? AnyCodableDecoder.decode(T.self, from: value)
        #expect(inMemory == viaJSON, "\(value) as \(T.self): \(String(describing: inMemory)) ≠ JSON's \(String(describing: viaJSON))")
    }

    @Test("scalars decode as JSONDecoder reads them", arguments: values)
    func scalars(value: AnyCodable) throws {
        try agree(Bool.self, value)
        try agree(String.self, value)
        try agree(Int.self, value)
        try agree(Int8.self, value)
        try agree(UInt.self, value)
        try agree(Double.self, value)
        try agree(Float.self, value)
        try agree(Int?.self, value)
    }

    @Test("containers and AnyCodable decode as JSONDecoder reads them", arguments: values)
    func containers(value: AnyCodable) throws {
        try agree(AnyCodable.self, value)
        try agree([AnyCodable].self, value)
        try agree([String: AnyCodable].self, value)
        try agree([Double].self, value)
        try agree([String: Double?].self, value)
    }

    @Test("model types decode as JSONDecoder reads them", arguments: values)
    func modelTypes(value: AnyCodable) throws {
        try agree(PenSizing.self, value)
        try agree(PenValue<Double>.self, value)
        try agree(PenFills.self, value)
        try agree(PenCornerRadius.self, value)
        try agree(PenPadding.self, value)
        try agree(PenDescendantOverride.self, value)
        try agree(PenNode.self, value)
        try agree([PenNode].self, value)
    }

    @Test("AnyCodable reads each JSON shape from text as its own case")
    func anyCodableFromText() throws {
        let text = #"[null, true, false, 1, -0, 2.5, 3.0, 1e20, "s", "1", "true", [1, "a"], {"k": null}]"#
        let decoded = try JSONDecoder().decode([AnyCodable].self, from: Data(text.utf8))
        #expect(decoded == [
            .null, .bool(true), .bool(false), .int(1), .int(0), .double(2.5), .int(3), .double(1e20),
            .string("s"), .string("1"), .string("true"), .array([.int(1), .string("a")]), .dictionary(["k": .null]),
        ])
    }
}
