//
//  FileTokenLibraryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// The library's own write paths — encode, the flat store, the collaborative store and
/// ``PenFileTransaction`` — keep a document's `fileToken` exactly, and invent none.
///
/// Every `woodcase` write verb goes through these, so this is the root of the guarantee
/// `FileTokenPreservationTests` pins verb by verb through the binary.
@Suite("fileToken in the library's write paths")
struct FileTokenLibraryTests {
    // MARK: - Helpers

    /// A token with characters a careless encoder would change.
    private static let token = "Tok/en+é-0001=="

    private static func json(token: String?) -> String {
        let field = token.map { #""fileToken": "\#($0)","# } ?? ""
        return """
        {
          "version": "\(PenDocument.currentFormatVersion)",
          \(field)
          "children": [
            { "type": "text", "id": "Ttl01", "name": "Title", "content": "Hello" }
          ]
        }
        """
    }

    /// A temporary .pen file holding the document, removed when `body` returns.
    private static func withFile<T>(
        token: String?, _ body: (URL) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileTokenLibraryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("doc.pen")
        try Data(json(token: token).utf8).write(to: url)
        return try await body(url)
    }

    /// The top-level `fileToken` of a file on disk, read without the library's parser.
    private static func tokenOnDisk(_ url: URL) throws -> String? {
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        return object["fileToken"] as? String
    }

    private static let tokens: [String?] = [token, nil]

    // MARK: - Encoding

    @Test("Parse then encode keeps the token, or the lack of one", arguments: tokens)
    func encodeKeeps(token: String?) throws {
        let document = try PenParser.parse(Data(Self.json(token: token).utf8))
        #expect(document.fileToken == token)

        let encoded = try PenParser.encodeForFile(document)

        let object = try #require(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(object["fileToken"] as? String == token)
    }

    // MARK: - The flat store

    @Test("The flat store materializes the document with its token", arguments: tokens)
    func flatStoreKeeps(token: String?) throws {
        let document = try PenParser.parse(Data(Self.json(token: token).utf8))

        #expect(EditableDocument(from: document).materialize().fileToken == token)
        #expect(EditableDocument(from: document, peerID: PeerID(rawValue: "peer")).materialize().fileToken == token)
    }

    // MARK: - The transaction every verb shares

    @Test("A committed edit keeps the token, or the lack of one", arguments: tokens)
    func transactionKeeps(token: String?) async throws {
        try await Self.withFile(token: token) { url in
            try await PenFileTransaction.run(at: url, identity: "ana") { document, recorder in
                var node = try #require(document.nodes["Ttl01"])
                node.common.name = "Renamed"
                try recorder.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: "Ttl01", common: node.common)))
            }

            #expect(try Self.tokenOnDisk(url) == token)
            #expect(try PenParser.parse(contentsOf: url).children.first?.common.name == "Renamed")
        }
    }

    @Test("An app's save of its session keeps the token, or the lack of one", arguments: tokens)
    func saveKeeps(token: String?) async throws {
        try await Self.withFile(token: token) { url in
            let author = Author(name: "ben", peerID: PeerID(rawValue: "peer-ben"))
            let session = try DocumentSession(
                document: PenParser.parse(contentsOf: url), author: author, file: url, merger: .threeWay
            )
            let rename = EditOperation.setProperties(
                EditOperation.SetProperties(nodeID: "Ttl01", properties: ["common.name": .string("Saved")])
            )
            let change = try session.submit(.local(LocalEdit(operations: [rename])))

            let outcome = try await PenFileTransaction.save(session.snapshot(), changes: [change], to: url)

            #expect(outcome == .wrote)
            #expect(try Self.tokenOnDisk(url) == token)
            #expect(try PenParser.parse(contentsOf: url).children.first?.common.name == "Saved")
        }
    }

    @Test("Creating a file from a document keeps its token, or the lack of one", arguments: tokens)
    func createKeeps(token: String?) async throws {
        let document = try PenParser.parse(Data(Self.json(token: token).utf8))
        try await Self.withFile(token: nil) { existing in
            let url = existing.deletingLastPathComponent().appendingPathComponent("created.pen")

            try await PenFileTransaction.create(at: url, document: document, identity: "ana")

            #expect(try Self.tokenOnDisk(url) == token)
        }
    }

    @Test("A dry run leaves the token alone", arguments: tokens)
    func dryRunKeeps(token: String?) async throws {
        try await Self.withFile(token: token) { url in
            try await PenFileTransaction.run(at: url, identity: "ana", effect: .dryRun) { document, recorder in
                var node = try #require(document.nodes["Ttl01"])
                node.common.name = "Renamed"
                try recorder.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: "Ttl01", common: node.common)))
            }

            #expect(try Self.tokenOnDisk(url) == token)
        }
    }
}
