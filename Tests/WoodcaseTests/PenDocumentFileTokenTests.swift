//
//  PenDocumentFileTokenTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

/// Covers the top-level `fileToken` Pen.app writes on every save.
struct PenDocumentFileTokenTests {
    private func goldenURL(_ name: String) throws -> URL {
        try #require(
            Bundle.module.url(forResource: name, withExtension: "pen", subdirectory: "Fixtures/v2.17"),
            "Missing 2.17 golden \(name).pen"
        )
    }

    @Test("A Pen.app 2.17 file's fileToken survives a parse/encode round-trip")
    func roundTripsThroughParser() throws {
        let url = try goldenURL("parser-stroke-variants")
        let parsed = try PenParser.parse(contentsOf: url)
        #expect(parsed.fileToken == "1aa7be13-0695-43a9-aaee-4982692fc94d")

        let encoded = try PenParser.encode(parsed)
        #expect(String(decoding: encoded, as: UTF8.self).contains("1aa7be13-0695-43a9-aaee-4982692fc94d"))

        let reparsed = try PenParser.parse(encoded)
        #expect(reparsed == parsed)
        #expect(reparsed.fileToken == parsed.fileToken)
    }

    @Test("A document without a fileToken decodes to nil and encodes nothing")
    func absentTokenIsOmitted() throws {
        let doc = try PenParser.parse(Data(#"{"version":"2.17","children":[]}"#.utf8))
        #expect(doc.fileToken == nil)
        let json = try PenParser.encodeToString(doc)
        #expect(!json.contains("fileToken"))
    }

    @Test("A fileToken is never generated")
    func neverGenerated() throws {
        let doc = PenDocument(children: [])
        #expect(doc.fileToken == nil)
        let migrated = try PenParser.parse(Data(#"{"version":"2.9","children":[]}"#.utf8))
        #expect(migrated.fileToken == nil)
    }

    @Test("A legacy document's fileToken is preserved through migration")
    func preservedThroughMigration() throws {
        let json = #"{"version":"2.9","fileToken":"abc-123","children":[]}"#
        let doc = try PenParser.parse(Data(json.utf8))
        #expect(doc.version == PenDocument.currentFormatVersion)
        #expect(doc.fileToken == "abc-123")
    }

    @Test("A fileToken survives a round trip through the editing layer")
    @MainActor
    func roundTripsThroughEditableDocument() throws {
        let document = try PenParser.parse(contentsOf: goldenURL("parser-stroke-variants"))
        let editable = EditableDocument(from: document)
        #expect(editable.fileToken == document.fileToken)
        #expect(editable.materialize().fileToken == document.fileToken)
    }

    @Test("A fileToken survives an off-actor materialization")
    func roundTripsThroughMaterializeSnapshot() async throws {
        let document = try PenParser.parse(contentsOf: goldenURL("parser-stroke-variants"))
        let editable = await EditableDocument(from: document)
        let materialized = await editable.materializeSnapshot()
        #expect(materialized.fileToken == document.fileToken)
    }
}
