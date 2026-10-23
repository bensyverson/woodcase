//
//  BundleTransactionTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Every read and write accepts a `.umbra` bundle where it accepts a `.pen`, and goes to
/// the `document.pen` inside it, with the history in the bundle's own `history/`.
///
/// Changed 2026-10-23 (leaf KAJTF3): the history moved from `.woodcase/activity.jsonl` to
/// `history/`, one file per writer, and the bundle now holds its own `.gitignore` for its
/// local `.woodcase/`.
struct BundleTransactionTests {
    private static let nodeID = "jSUCH"

    private static func rename(_ name: String) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.name": .string(name)]))
    }

    /// A bundle holding a canonical copy of `layout-vertical`, in a fresh directory.
    private struct Scratch {
        let directory: URL
        let bundle: URL

        init() throws {
            directory = FileManager.default.temporaryDirectory
                .appendingPathComponent("BundleTransactionTests-\(UUID().uuidString)")
                .resolvingSymlinksInPath()
            bundle = directory.appendingPathComponent("Design.umbra")
            try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
            let source = try #require(Bundle.module.url(
                forResource: "layout-vertical", withExtension: "pen", subdirectory: "Fixtures"
            ))
            try PenParser.encodeForFile(PenParser.parse(Data(contentsOf: source)))
                .write(to: bundle.appendingPathComponent("document.pen"))
        }

        var document: URL {
            bundle.appendingPathComponent("document.pen")
        }

        var log: ActivityLog {
            ActivityLogLocation.log(for: bundle, environment: [:])
        }

        func remove() {
            try? FileManager.default.removeItem(at: directory)
        }
    }

    @Test("PenParser reads a bundle by its document.pen")
    func parserReadsABundle() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }

        #expect(try PenParser.parse(contentsOf: scratch.bundle) == PenParser.parse(contentsOf: scratch.document))
    }

    @Test("a logged transaction on a bundle writes document.pen and logs in the bundle")
    func runWritesTheDocumentAndLogsInTheBundle() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }

        let outcome = try await PenFileTransaction.run(at: scratch.bundle, identity: "ana") { _, recorder in
            try recorder.apply(Self.rename("Bundled"))
        }

        #expect(outcome.didWrite)
        let document = try EditableDocument(from: PenParser.parse(contentsOf: scratch.document))
        #expect(document.nodes[Self.nodeID]?.common.name == "Bundled")
        let rows = try ActivityReader(log: scratch.log).read().events
        #expect(rows.map(\.op) == [.set])
        #expect(rows.first?.file == ActivityEvent.canonicalPath(for: scratch.document))
    }

    @Test("a write leaves no temporary file in the bundle's root")
    func temporaryFilesStayInTheStateDirectory() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }

        try await PenFileTransaction.run(at: scratch.bundle, identity: "ana") { _, recorder in
            try recorder.apply(Self.rename("Clean"))
        }

        let root = try FileManager.default.contentsOfDirectory(atPath: scratch.bundle.path)
        #expect(root.sorted() == [".gitignore", ".woodcase", "document.pen", "history"])
    }

    @Test("a read of a bundle sees its document, with relative paths resolving inside it")
    func readSeesTheDocument() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }

        let outcome = try await PenFileTransaction.read(at: scratch.bundle) { document in
            document.readContext.sourceURL
        }

        #expect(outcome.value?.path == scratch.document.path)
    }

    @Test("create on a .umbra path makes the bundle and logs `new` inside it")
    func createMakesABundle() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let fresh = scratch.directory.appendingPathComponent("Fresh.umbra")

        let outcome = try await PenFileTransaction.create(
            at: fresh, document: PenDocument(children: []), identity: "ana"
        )

        #expect(outcome.didWrite)
        #expect(FileManager.default.fileExists(atPath: fresh.appendingPathComponent("document.pen").path))
        let log = ActivityLogLocation.log(for: fresh, environment: [:])
        #expect(try ActivityReader(log: log).read().events.map(\.op) == [.new])
        let root = try FileManager.default.contentsOfDirectory(atPath: fresh.path)
        #expect(root.sorted() == [".gitignore", ".woodcase", "document.pen", "history"])
    }

    @Test("create refuses a bundle that already holds a document")
    func createRefusesAnExistingBundle() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }

        await #expect(throws: PenFileError.self) {
            try await PenFileTransaction.create(at: scratch.bundle, document: PenDocument(children: []), identity: "ana")
        }
    }

    @Test("an app's save to a bundle writes document.pen and logs in the bundle")
    func saveToABundle() async throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let ben = Author(name: "ben", peerID: PeerID(rawValue: "peer-ben"))
        let session = try DocumentSession(
            document: PenParser.parse(contentsOf: scratch.bundle), author: ben, file: scratch.bundle, merger: .threeWay
        )
        let change = try session.submit(.local(LocalEdit(operations: [Self.rename("Saved")])))

        let outcome = try await PenFileTransaction.save(session.snapshot(), changes: [change], to: scratch.bundle)

        #expect(outcome == .wrote)
        #expect(try ActivityReader(log: scratch.log).read().events.map(\.identity) == ["ben"])
        let root = try FileManager.default.contentsOfDirectory(atPath: scratch.bundle.path)
        #expect(root.sorted() == [".gitignore", ".woodcase", "document.pen", "history"])
    }

    @Test("an import of another bundle reads that bundle's document")
    func importsReadBundles() throws {
        let scratch = try Scratch()
        defer { scratch.remove() }
        let kit = scratch.directory.appendingPathComponent("Kit.umbra")
        try FileManager.default.copyItem(at: scratch.bundle, to: kit)
        var host = try PenParser.parse(contentsOf: scratch.bundle)
        host.imports = ["kit": "../Kit.umbra"]
        try PenParser.encodeForFile(host).write(to: scratch.document)

        let libraries = PenLibraries.load(importedBy: host, at: scratch.document)

        #expect(libraries.problems.isEmpty)
        #expect(libraries.documents["../Kit.umbra"] != nil)
    }
}
