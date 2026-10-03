//
//  PenVersionGateTests.swift
//  WoodcaseTests
//
//  Created by Claude on 2026-08-29.
//

import Foundation
import Testing
import Woodcase

/// Covers ``PenParser``'s dispatch on the document's declared format version.
struct PenVersionGateTests {
    // MARK: - Helpers

    private func document(version: String?, children: String = "[]") -> Data {
        if let version {
            Data(#"{"version":"\#(version)","children":\#(children)}"#.utf8)
        } else {
            Data(#"{"children":\#(children)}"#.utf8)
        }
    }

    private let rectangle = #"[{"id":"r","type":"rectangle","width":50,"height":50}]"#

    // MARK: - Legacy (2.8 … 2.10)

    @Test("Legacy versions are migrated and report the model's version", arguments: ["2.8", "2.9", "2.10"])
    func legacyVersionsMigrate(version: String) throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: version, children: rectangle), diagnostics: diagnostics)
        #expect(doc.version == PenDocument.currentFormatVersion)
        #expect(doc.children.count == 1)
        #expect(!diagnostics.hasIssues)
    }

    @Test("A 2.9 fixture parses with the model's version")
    func legacyFixtureReportsCurrentVersion() throws {
        let url = try #require(
            Bundle.module.url(
                forResource: "parser-empty-document", withExtension: "pen",
                subdirectory: "Fixtures/v2.9"
            )
        )
        let doc = try PenParser.parse(contentsOf: url)
        #expect(doc.version == PenDocument.currentFormatVersion)
    }

    @Test("Versions below 2.8 are migrated with a warning")
    func belowOldestLegacyWarns() throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.3"), diagnostics: diagnostics)
        #expect(doc.version == PenDocument.currentFormatVersion)
        #expect(diagnostics.diagnostics.count == 1)
        let diagnostic = try #require(diagnostics.diagnostics.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.stage == .migration)
        #expect(diagnostic.message.contains("2.3"))
    }

    // MARK: - Never observed (2.11 … 2.16, 2.18)

    @Test("Versions never observed in the wild decode with a warning", arguments: ["2.11", "2.14", "2.16", "2.18"])
    func neverObservedVersionsWarn(version: String) throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: version, children: rectangle), diagnostics: diagnostics)
        #expect(doc.version == PenDocument.currentFormatVersion)
        #expect(doc.children.count == 1)
        #expect(diagnostics.diagnostics.count == 1)
        let diagnostic = try #require(diagnostics.diagnostics.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.stage == .migration)
        #expect(diagnostic.message.contains(version))
    }

    // MARK: - Observed (2.17, 2.19) and current (2.20)

    @Test("2.17 and 2.19, which Pen wrote before 1.2.15, decode without diagnostics and report the model's version",
          arguments: ["2.17", "2.19"])
    func observedOlderVersionIsSilent(version: String) throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: version, children: rectangle), diagnostics: diagnostics)
        #expect(doc.version == PenDocument.currentFormatVersion)
        #expect(!diagnostics.hasIssues)
    }

    @Test("Version 2.20 decodes without diagnostics")
    func currentVersionIsSilent() throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: "2.20", children: rectangle), diagnostics: diagnostics)
        #expect(doc.version == "2.20")
        #expect(!diagnostics.hasIssues)
    }

    // MARK: - Newer minor

    @Test("A newer 2.x minor decodes with one notice and keeps its declared version", arguments: ["2.21", "2.22", "2.99"])
    func newerMinorIsANotice(version: String) throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: version, children: rectangle), diagnostics: diagnostics)
        #expect(doc.version == version)
        #expect(doc.children.count == 1)
        #expect(diagnostics.diagnostics.count == 1)
        let diagnostic = try #require(diagnostics.diagnostics.first)
        #expect(diagnostic.severity == .notice)
        #expect(diagnostic.stage == .migration)
        #expect(diagnostic.message.contains(version))
        #expect(diagnostic.message.contains("written back as \(version)"))
    }

    @Test("A newer minor re-encodes with its declared version, never the model's")
    func newerMinorRoundTripsItsVersion() throws {
        let doc = try PenParser.parse(document(version: "2.21", children: rectangle))
        let reparsed = try PenParser.parse(PenParser.encode(doc))
        #expect(reparsed.version == "2.21")
    }

    // MARK: - Different major

    @Test("A different major that decodes as a document reads with a warning", arguments: ["3.0", "1.4"])
    func differentMajorReadsWithAWarning(version: String) throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: version, children: rectangle), diagnostics: diagnostics)
        #expect(doc.version == version)
        #expect(doc.children.count == 1)
        #expect(diagnostics.diagnostics.count == 1)
        let diagnostic = try #require(diagnostics.diagnostics.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.stage == .migration)
        #expect(diagnostic.message.contains(version))
        #expect(diagnostic.message.contains("read-only"))
    }

    @Test("A different major with no node this build models throws differentMajor", arguments: ["1", "1.0", "3.0", "0.1"])
    func differentMajorWithNothingModeledThrows(version: String) throws {
        let thrown = #expect(throws: PenParserError.self) {
            try PenParser.parse(document(version: version))
        }
        guard case let .differentMajor(_, reported, reason)? = thrown else {
            Issue.record("Expected differentMajor, got \(String(describing: thrown))")
            return
        }
        #expect(reported == version)
        #expect(reason.contains("no node"))
    }

    @Test("A different major whose nodes lack an id or a type throws differentMajor naming the node")
    func differentMajorWithoutIdentityThrows() throws {
        let thrown = #expect(throws: PenParserError.self) {
            try PenParser.parse(document(version: "3.0", children: #"[{"type":"rectangle","width":5,"height":5}]"#))
        }
        guard case let .differentMajor(_, _, reason)? = thrown else {
            Issue.record("Expected differentMajor, got \(String(describing: thrown))")
            return
        }
        #expect(reason.contains("children[0]"))
    }

    @Test("A different major whose modeled key changed shape throws differentMajor naming the key")
    func differentMajorWithATypeConflictThrows() throws {
        let children = #"[{"id":"r","type":"rectangle","width":{"min":5},"height":5}]"#
        let thrown = #expect(throws: PenParserError.self) {
            try PenParser.parse(document(version: "3.0", children: children))
        }
        guard case let .differentMajor(_, _, reason)? = thrown else {
            Issue.record("Expected differentMajor, got \(String(describing: thrown))")
            return
        }
        #expect(reason.contains("children[0].width"))
    }

    @Test("differentMajor says the major differs, what failed, and never claims only older 2.x is read")
    func differentMajorDescription() {
        let error = PenParserError.differentMajor(url: nil, version: "3.0", reason: "children is missing")
        #expect(error.description.contains("\"3.0\""))
        #expect(error.description.contains("different major version"))
        #expect(error.description.contains("children is missing"))
        #expect(!error.description.contains("earlier 2.x"))
    }

    // MARK: - Unsupported

    @Test("An unparsable version throws unsupportedVersion", arguments: ["", "banana", "2.9.1"])
    func unparsableVersionThrows(version: String) throws {
        let thrown = #expect(throws: PenParserError.self) {
            try PenParser.parse(document(version: version))
        }
        guard case let .unsupportedVersion(_, reported)? = thrown else {
            Issue.record("Expected unsupportedVersion, got \(String(describing: thrown))")
            return
        }
        #expect(reported == version)
    }

    @Test("A non-string version throws unsupportedVersion")
    func nonStringVersionThrows() {
        let data = Data(#"{"version":2.17,"children":[]}"#.utf8)
        #expect(throws: PenParserError.self) {
            try PenParser.parse(data)
        }
    }

    @Test("unsupportedVersion says the value is not a major.minor version, and never claims only older 2.x is read")
    func unsupportedVersionDescription() {
        let error = PenParserError.unsupportedVersion(url: nil, version: "banana")
        #expect(error.description.contains("\"banana\""))
        #expect(error.description.contains("major.minor"))
        #expect(!error.description.contains("earlier 2.x"))
        #expect(error.url == nil)
    }

    @Test("A version read from a file names the file")
    func unsupportedVersionNamesItsFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("PenVersionGateTests-\(UUID().uuidString).pen")
        try document(version: "3.0").write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let thrown = #expect(throws: PenParserError.self) {
            try PenParser.parse(contentsOf: url)
        }
        #expect(thrown?.url == url)
        #expect(thrown?.description.contains(url.path) == true)
    }

    // MARK: - Missing version

    @Test("A missing version field is treated as legacy with a warning")
    func missingVersionIsLegacy() throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(document(version: nil, children: rectangle), diagnostics: diagnostics)
        #expect(doc.version == PenDocument.currentFormatVersion)
        #expect(doc.children.count == 1)
        #expect(diagnostics.diagnostics.count == 1)
        let diagnostic = try #require(diagnostics.diagnostics.first)
        #expect(diagnostic.severity == .warning)
        #expect(diagnostic.stage == .migration)
        #expect(diagnostic.message.lowercased().contains("version"))
    }

    // MARK: - Diagnostics are optional

    @Test("Parsing without a diagnostic collector still succeeds")
    func diagnosticsAreOptional() throws {
        let doc = try PenParser.parse(document(version: "2.11", children: rectangle))
        #expect(doc.version == PenDocument.currentFormatVersion)
    }

    @Test("Parsing a string dispatches through the gate")
    func stringParsingUsesGate() throws {
        let diagnostics = PenDiagnosticCollector()
        let doc = try PenParser.parse(#"{"version":"2.9","children":[]}"#, diagnostics: diagnostics)
        #expect(doc.version == PenDocument.currentFormatVersion)
    }

    // MARK: - Malformed input

    @Test("Invalid JSON still throws decodingFailed", arguments: ["not valid json", "[]"])
    func malformedInputThrowsDecodingFailed(input: String) {
        let thrown = #expect(throws: PenParserError.self) {
            try PenParser.parse(Data(input.utf8))
        }
        guard case .decodingFailed? = thrown else {
            Issue.record("Expected decodingFailed, got \(String(describing: thrown))")
            return
        }
    }
}
