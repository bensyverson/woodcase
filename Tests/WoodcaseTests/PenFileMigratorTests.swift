//
//  PenFileMigratorTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

/// Covers ``PenFileMigrator`` — the library half of `woodcase migrate`.
struct PenFileMigratorTests {
    // MARK: - Fixtures

    private static let legacyJSON = """
    {
      "version": "2.9",
      "children": [
        {
          "type": "rectangle",
          "id": "r1",
          "width": 100,
          "height": 50,
          "stroke": {
            "fill": "#FF0000",
            "thickness": 2,
            "align": "outside",
            "cap": "square",
            "dashPattern": [4, 2]
          }
        }
      ]
    }
    """

    private static let currentJSON = """
    {
      "version": "2.19",
      "children": [
        { "type": "rectangle", "id": "r1", "width": 100, "height": 50 }
      ]
    }
    """

    private static func data(_ string: String) -> Data {
        Data(string.utf8)
    }

    private static func text(_ data: Data) -> String {
        String(decoding: data, as: UTF8.self)
    }

    // MARK: - Migration

    @Test("A legacy document is rewritten in the current format")
    func legacyDocumentIsRewritten() throws {
        let outcome = try PenFileMigrator.migrate(Self.data(Self.legacyJSON))
        let reparsed = try PenParser.parse(outcome.data)
        #expect(reparsed.version == PenDocument.currentFormatVersion)
        #expect(Self.text(outcome.data).contains("\"version\": \"2.19\""))
    }

    @Test("The source's declared version is reported")
    func declaredVersionIsReported() throws {
        let outcome = try PenFileMigrator.migrate(Self.data(Self.legacyJSON))
        #expect(outcome.declaredVersion == "2.9")
        #expect(outcome.wasAlreadyCurrent == false)
    }

    @Test("A document already at the current version is recognized")
    func currentDocumentIsRecognized() throws {
        let outcome = try PenFileMigrator.migrate(Self.data(Self.currentJSON))
        #expect(outcome.declaredVersion == "2.19")
        #expect(outcome.wasAlreadyCurrent)
    }

    @Test("A document with no version reports none and is not current")
    func missingVersionIsReportedAsNil() throws {
        let outcome = try PenFileMigrator.migrate(Self.data(#"{"children": []}"#))
        #expect(outcome.declaredVersion == nil)
        #expect(outcome.wasAlreadyCurrent == false)
    }

    // MARK: - On-disk shape

    @Test("Output is pretty-printed with two-space indentation and a trailing newline")
    func outputIsPrettyPrinted() throws {
        let outcome = try PenFileMigrator.migrate(Self.data(Self.legacyJSON))
        let string = Self.text(outcome.data)
        #expect(string.hasPrefix("{\n  \""))
        #expect(string.hasSuffix("}\n"))
    }

    @Test("Output keys are sorted")
    func outputKeysAreSorted() throws {
        let outcome = try PenFileMigrator.migrate(Self.data(Self.legacyJSON))
        let string = Self.text(outcome.data)
        let children = try #require(string.range(of: "\"children\""))
        let version = try #require(string.range(of: "\"version\""))
        #expect(children.lowerBound < version.lowerBound)
    }

    @Test("Slashes in URLs are not escaped")
    func slashesAreNotEscaped() throws {
        let json = """
        {
          "version": "2.9",
          "children": [
            {
              "type": "rectangle", "id": "r1", "width": 10, "height": 10,
              "fill": { "type": "image", "url": "https://example.com/a.png" }
            }
          ]
        }
        """
        let outcome = try PenFileMigrator.migrate(Self.data(json))
        #expect(Self.text(outcome.data).contains("https://example.com/a.png"))
    }

    @Test("A string value that looks like a key separator is left alone")
    func keySeparatorInsideAStringValueSurvives() throws {
        let json = """
        {
          "version": "2.9",
          "children": [
            { "type": "text", "id": "t1", "content": "before : after" }
          ]
        }
        """
        let outcome = try PenFileMigrator.migrate(Self.data(json))
        #expect(Self.text(outcome.data).contains("\"before : after\""))
    }

    @Test("Migrating an already-migrated document is byte-stable")
    func migrationIsIdempotent() throws {
        let once = try PenFileMigrator.migrate(Self.data(Self.legacyJSON))
        let twice = try PenFileMigrator.migrate(once.data)
        #expect(once.data == twice.data)
    }

    // MARK: - Diagnostics and errors

    @Test("Discarded legacy data is reported through the collector")
    func discardedDataIsReported() throws {
        let diagnostics = PenDiagnosticCollector()
        _ = try PenFileMigrator.migrate(Self.data(Self.legacyJSON), diagnostics: diagnostics)
        #expect(diagnostics.diagnostics.contains { $0.message.contains("dashPattern") })
    }

    @Test("Invalid JSON throws a parser error")
    func invalidJSONThrows() {
        #expect(throws: PenParserError.self) {
            _ = try PenFileMigrator.migrate(Self.data("not json"))
        }
    }

    @Test("An unreadable major version throws")
    func unsupportedMajorThrows() {
        #expect(throws: PenParserError.self) {
            _ = try PenFileMigrator.migrate(Self.data(#"{"version": "3.0", "children": []}"#))
        }
    }
}
