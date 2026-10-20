//
//  FigmaClipboardCaptureTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Decodes every raw capture in a local, gitignored folder — desktop app, Safari and
/// Chromium copies alike — when `FIGMA_CASES` names it (Penumbra's `local/figma-cases/`).
///
/// The captures carry real file keys, so they are never committed and this suite is off
/// by default. Each capture's schema must equal the committed `schema.kiwi`, and a case
/// with a committed `message.kiwi` must decode to it once its file key is replaced by the
/// fixtures' placeholder, as `scripts/figma-curate` does.
///
/// ```sh
/// FIGMA_CASES=../Penumbra/local/figma-cases swift test --filter FigmaClipboardCaptureTests
/// ```
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FIGMA_CASES"] != nil, "set FIGMA_CASES to a folder of raw captures"))
struct FigmaClipboardCaptureTests {
    /// The capture folder `FIGMA_CASES` names, if any.
    static let folder: URL? = ProcessInfo.processInfo.environment["FIGMA_CASES"].map {
        URL(fileURLWithPath: $0, isDirectory: true)
    }

    /// Every `<case>.html` in the folder, by case name.
    static func captures() throws -> [String: Data] {
        guard let folder else { return [:] }
        let names = try FileManager.default.contentsOfDirectory(atPath: folder.path)
        var captures: [String: Data] = [:]
        for name in names where name.hasSuffix(".html") {
            captures[String(name.dropLast(5))] = try Data(contentsOf: folder.appendingPathComponent(name))
        }
        return captures
    }

    /// `message` with `fileKey` replaced, in place, by the same-length placeholder.
    static func redacted(_ message: Data, fileKey: String) -> Data {
        let key = Data(fileKey.utf8)
        let placeholder = Data(String((FigmaClipboardFixtures.fixtureFileKey + String(repeating: "0", count: key.count)).prefix(key.count)).utf8)
        var result = message
        while let range = result.range(of: key) {
            result.replaceSubrange(range, with: placeholder)
        }
        return result
    }

    @Test("Every local capture decodes, with the committed schema")
    func everyCaptureDecodes() throws {
        let captures = try Self.captures()
        try #require(!captures.isEmpty)
        let schema = try KiwiFixtures.schemaData()
        for (name, html) in captures.sorted(by: { $0.key < $1.key }) {
            let clipboard = try FigmaClipboardDecoder().decode(html: html)
            let lengths = clipboard.container.chunks.map(\.count)
            print("\(name): fig-kiwi \(clipboard.container.version), chunks \(lengths), \(clipboard.metadata.editorType ?? "?")")
            #expect(clipboard.schemaData == schema, "\(name)")
            #expect(clipboard.message["type"]?.enumName == "NODE_CHANGES", "\(name)")
            guard KiwiFixtures.caseIDs.contains(name), let key = clipboard.metadata.fileKey else { continue }
            #expect(try Self.redacted(clipboard.messageData, fileKey: key) == KiwiFixtures.messageData(name), "\(name)")
        }
    }

    /// Every blob index `value` holds at any depth, by the field that names it.
    static func blobReferences(in value: KiwiValue, into references: inout [(field: String, index: UInt32)]) {
        switch value {
        case let .array(values):
            for element in values {
                blobReferences(in: element, into: &references)
            }
        case let .structure(record), let .message(record):
            for (name, field) in record.fields where name != "blobs" {
                if name == "vectorNetworkBlob" || name == "commandsBlob", let index = field.uintValue {
                    references.append((name, index))
                }
                blobReferences(in: field, into: &references)
            }
        default:
            break
        }
    }

    @Test("Every blob a capture references decodes as the kind its field names")
    func everyBlobDecodes() throws {
        let captures = try Self.captures()
        try #require(!captures.isEmpty)
        for (name, html) in captures.sorted(by: { $0.key < $1.key }) {
            let clipboard = try FigmaClipboardDecoder().decode(html: html)
            let table = try clipboard.blobTable()
            var references: [(field: String, index: UInt32)] = []
            Self.blobReferences(in: .message(clipboard.message), into: &references)
            var networks = 0
            var paths = 0
            for reference in references {
                if reference.field == "vectorNetworkBlob" {
                    let network = try table.vectorNetwork(at: reference.index)
                    for region in network.regions.indices {
                        _ = try network.path(ofRegion: region)
                    }
                    networks += 1
                } else {
                    _ = try table.path(at: reference.index)
                    paths += 1
                }
            }
            let referenced = Set(references.map(\.index))
            print("\(name): \(table.blobs.count) blobs, \(networks) network and \(paths) path references, \(table.blobs.count - referenced.count) unreferenced")
            #expect(referenced.count == table.blobs.count, "\(name): every blob is referenced")
        }
    }

    @Test("The desktop, Safari and Brave copies of V1 decode to the same nodes")
    func browserCopiesMatchDesktop() throws {
        let captures = try Self.captures()
        let names = ["V1", "V1-browser", "V1-brave"]
        let decoded = try names.map { name in
            try FigmaClipboardDecoder().decode(html: #require(captures[name], "\(name).html"))
        }
        let nodeNames = decoded.map { clipboard in
            clipboard.message["nodeChanges"]?.arrayValue?.compactMap { $0["name"]?.stringValue } ?? []
        }
        #expect(!nodeNames[0].isEmpty)
        #expect(nodeNames[1] == nodeNames[0])
        #expect(nodeNames[2] == nodeNames[0])
    }
}
