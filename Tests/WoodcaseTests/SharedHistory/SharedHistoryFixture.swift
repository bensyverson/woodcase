//
//  SharedHistoryFixture.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A `.umbra` bundle holding a canonical copy of `layout-vertical`, in a fresh scratch
/// directory that is a repository root unless asked otherwise.
struct SharedHistoryFixture {
    /// The scratch directory: the bundle's folder, and a repository root when asked.
    let directory: URL

    /// The bundle.
    let bundle: URL

    /// Makes the scratch directory and the bundle.
    ///
    /// - Parameter repository: Whether the scratch directory holds a `.git`.
    init(repository: Bool = true) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SharedHistory-\(UUID().uuidString)")
            .resolvingSymlinksInPath()
        bundle = directory.appendingPathComponent("Design.umbra")
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        if repository {
            try FileManager.default.createDirectory(
                at: directory.appendingPathComponent(".git"), withIntermediateDirectories: true
            )
        }
        let source = try #require(Bundle.module.url(
            forResource: "layout-vertical", withExtension: "pen", subdirectory: "Fixtures"
        ))
        try PenParser.encodeForFile(PenParser.parse(Data(contentsOf: source))).write(to: document)
    }

    /// The node every edit renames.
    static let nodeID = "jSUCH"

    /// The bundle's `document.pen`.
    var document: URL {
        bundle.appendingPathComponent("document.pen")
    }

    /// The bundle's shared history directory.
    var history: URL {
        bundle.appendingPathComponent("history", isDirectory: true)
    }

    /// The bundle's log, as a writer on `device` would append to it.
    func log(device: String = "grace") -> ActivityLog {
        var log = ActivityLogLocation.log(for: bundle, environment: [:])
        log.device = device
        return log
    }

    /// The names in the history directory, sorted; empty when it does not exist.
    func historyFiles() -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: history.path)) ?? []).sorted()
    }

    /// The document's revision on disk.
    func revision() throws -> String {
        try EditableDocument(from: PenParser.parse(contentsOf: document)).documentRevision
    }

    /// Rewrites the document without the lock or the log, as Pen.app or a hand edit would.
    func editOutsideTheLog(name: String) throws {
        let edited = try EditableDocument(from: PenParser.parse(contentsOf: document))
        try edited.apply(Self.rename(name))
        try PenParser.encodeForFile(edited.materialize()).write(to: document)
    }

    /// A row by `identity`, `seconds` after a fixed moment.
    static func event(_ identity: String, at seconds: TimeInterval, file: URL, revision: String = "r") -> ActivityEvent {
        ActivityEvent(
            time: Date(timeIntervalSince1970: 1_800_000_000 + seconds),
            identity: identity, file: file, op: .set, revision: revision
        )
    }

    /// Renames the fixture's node.
    static func rename(_ name: String) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.name": .string(name)]))
    }

    /// Deletes the scratch directory.
    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
