//
//  PenFormatVersionTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

struct PenFormatVersionTests {
    // MARK: - Parsing

    @Test(
        "Parses major.minor version strings",
        arguments: [
            ("2.17", 2, 17),
            ("2.9", 2, 9),
            ("2.10", 2, 10),
            ("10.0", 10, 0),
            ("2", 2, 0),
        ]
    )
    func parsesVersionString(input: String, major: Int, minor: Int) throws {
        let version = try #require(PenFormatVersion(input))
        #expect(version.major == major)
        #expect(version.minor == minor)
    }

    @Test(
        "Rejects malformed version strings",
        arguments: ["", "abc", "2.", ".9", "2.9.1", "v2.17", "2,9", " 2.9", "2.9 "]
    )
    func rejectsMalformedVersionString(input: String) {
        #expect(PenFormatVersion(input) == nil)
    }

    // MARK: - Ordering

    @Test("Orders by major, then minor")
    func ordering() {
        #expect(PenFormatVersion(major: 2, minor: 9) < PenFormatVersion(major: 2, minor: 10))
        #expect(PenFormatVersion(major: 2, minor: 17) < PenFormatVersion(major: 3, minor: 0))
        #expect(PenFormatVersion(major: 2, minor: 17) == PenFormatVersion(major: 2, minor: 17))
        #expect(!(PenFormatVersion(major: 2, minor: 17) < PenFormatVersion(major: 2, minor: 17)))
        #expect(PenFormatVersion(major: 3, minor: 0) > PenFormatVersion(major: 2, minor: 99))
    }

    // MARK: - Description

    @Test("Describes itself as major.minor")
    func describesItself() {
        #expect(PenFormatVersion(major: 2, minor: 17).description == "2.17")
        #expect(PenFormatVersion(major: 2, minor: 9).description == "2.9")
    }

    // MARK: - Well-known versions

    @Test("The current version is 2.20")
    func currentVersion() {
        #expect(PenFormatVersion.current == PenFormatVersion(major: 2, minor: 20))
        #expect(PenDocument.currentFormatVersion == "2.20")
    }

    @Test("The newest legacy version is 2.10")
    func newestLegacyVersion() {
        #expect(PenFormatVersion.newestLegacy == PenFormatVersion(major: 2, minor: 10))
    }

    // MARK: - Codable

    @Test("Round-trips through Codable as a plain string")
    func codableRoundTrip() throws {
        let version = PenFormatVersion(major: 2, minor: 17)
        let data = try JSONEncoder().encode([version])
        #expect(String(decoding: data, as: UTF8.self) == #"["2.17"]"#)
        let decoded = try JSONDecoder().decode([PenFormatVersion].self, from: data)
        #expect(decoded == [version])
    }

    @Test("Decoding a malformed version string fails")
    func codableRejectsMalformed() {
        let data = Data(#"["banana"]"#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([PenFormatVersion].self, from: data)
        }
    }
}
