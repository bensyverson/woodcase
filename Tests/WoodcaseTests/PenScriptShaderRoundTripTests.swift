//
//  PenScriptShaderRoundTripTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `Fixtures/v2.17/viewbox-experiment.pen` is the only fixture holding a `script`
/// node and a `shader` fill (see `project/2026-08-29-pen-2.17-migration.md`).
/// Round-tripping it losslessly is this slice's acceptance test — job criterion
/// "viewbox-experiment round-trips byte-stable modulo key order and fileToken".
struct PenScriptShaderRoundTripTests {
    private var fixtureURL: URL {
        get throws {
            try #require(Bundle.module.url(
                forResource: "viewbox-experiment", withExtension: "pen", subdirectory: "Fixtures/v2.17"
            ))
        }
    }

    @Test("viewbox-experiment decodes, encodes, and decodes again to an identical document")
    func decodeEncodeDecodeIsStable() throws {
        let data = try Data(contentsOf: fixtureURL)
        let first = try PenParser.parse(data)
        let reencoded = try PenParser.encode(first)
        let second = try PenParser.parse(reencoded)
        #expect(first == second)
    }

    @Test("viewbox-experiment's encoded JSON matches the original modulo key order and fileToken")
    func encodedJSONMatchesOriginal() throws {
        let originalData = try Data(contentsOf: fixtureURL)
        let document = try PenParser.parse(originalData)
        let encodedData = try PenParser.encode(document)

        var original = try #require(try JSONSerialization.jsonObject(with: originalData) as? [String: Any])
        var encoded = try #require(try JSONSerialization.jsonObject(with: encodedData) as? [String: Any])
        original.removeValue(forKey: "fileToken")
        encoded.removeValue(forKey: "fileToken")
        // A 2.17 file is read into the 2.19 model and written back as 2.19; nothing
        // else in this one changes (it has no inner shadow and no spread).
        #expect(encoded.removeValue(forKey: "version") as? String == PenDocument.currentFormatVersion)
        original.removeValue(forKey: "version")

        #expect(
            jsonValuesEqual(original, encoded),
            "Round-tripped JSON should match the original modulo key order and fileToken"
        )
    }

    // MARK: - Normalizing JSON comparison

    /// Structurally compares two `JSONSerialization` values, ignoring dictionary
    /// key order (dictionaries are inherently unordered) and treating any two
    /// numbers as equal when their `Double` values match — `JSONEncoder`'s
    /// choice of `32` vs `32.0` is not a semantic difference.
    private func jsonValuesEqual(_ lhs: Any, _ rhs: Any) -> Bool {
        if let l = lhs as? [String: Any], let r = rhs as? [String: Any] {
            guard Set(l.keys) == Set(r.keys) else { return false }
            return l.allSatisfy { key, value in jsonValuesEqual(value, r[key] as Any) }
        }
        if let l = lhs as? [Any], let r = rhs as? [Any] {
            guard l.count == r.count else { return false }
            return zip(l, r).allSatisfy { jsonValuesEqual($0, $1) }
        }
        if let l = lhs as? NSNumber, let r = rhs as? NSNumber {
            return l.doubleValue == r.doubleValue
        }
        if let l = lhs as? String, let r = rhs as? String {
            return l == r
        }
        if lhs is NSNull, rhs is NSNull {
            return true
        }
        return false
    }
}
