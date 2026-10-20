//
//  KiwiFixtures.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The committed Kiwi payloads in `Fixtures/Figma` (see its README).
///
/// The reader is format-generic; these happen to be the payloads we have. Their expected
/// values were derived with Evan Wallace's reference implementation (`kiwi-schema` 0.5.0
/// from npm, via `scripts/kiwi-oracle`), not with this reader, and the leading bytes were
/// checked by hand.
enum KiwiFixtures {
    /// The fixture schema's raw bytes.
    static func schemaData() throws -> Data {
        try data("schema", subdirectory: "Fixtures/Figma")
    }

    /// The fixture schema, decoded.
    static func schema() throws -> KiwiSchema {
        try KiwiSchema(binary: schemaData())
    }

    /// One case's raw message bytes.
    static func messageData(_ caseID: String) throws -> Data {
        try data("message", subdirectory: "Fixtures/Figma/\(caseID)")
    }

    /// The name of the definition these payloads use as their root.
    static let rootType = "Message"

    /// Every committed case that carries a message.
    static let caseIDs = ["C1", "G1", "I1", "L1", "M1a", "M1b", "M1c", "M1d", "M1e", "M1f", "P1", "R1", "T1", "V1"]

    private static func data(_ name: String, subdirectory: String) throws -> Data {
        let url = try #require(Bundle.module.url(
            forResource: name, withExtension: "kiwi", subdirectory: subdirectory
        ))
        return try Data(contentsOf: url)
    }
}
