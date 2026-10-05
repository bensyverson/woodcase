//
//  SaveFixture.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A temporary directory holding canonical copies of the `layout-vertical` fixture and
/// its own activity log, for the app-save suites.
struct SaveFixture {
    /// The node the save suites rename.
    static let nodeID = "jSUCH"

    /// The directory; remove it with ``remove()``.
    let directory: URL

    /// The log every write in the directory appends to.
    let log: ActivityLog

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SaveFixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        log = ActivityLog(home: directory.appendingPathComponent("home"))
    }

    /// A canonical copy of the fixture under `name`.
    func copy(named name: String = "layout-vertical.pen") throws -> URL {
        let source = try #require(Bundle.module.url(
            forResource: "layout-vertical", withExtension: "pen", subdirectory: "Fixtures"
        ))
        let url = directory.appendingPathComponent(name)
        try PenParser.encodeForFile(PenParser.parse(Data(contentsOf: source))).write(to: url)
        return url
    }

    /// Every row the log holds for `url`, oldest first.
    func events(for url: URL) throws -> [ActivityEvent] {
        try ActivityReader(log: log).read(file: url).events
    }

    /// A node of the fixture other than ``nodeID``.
    func otherNode(in url: URL) throws -> String {
        let document = try EditableDocument(from: PenParser.parse(contentsOf: url))
        return try #require(document.nodes.keys.sorted().first { $0 != Self.nodeID })
    }

    /// A rename of one node.
    static func rename(_ name: String, node: String = nodeID) -> EditOperation {
        .setProperties(EditOperation.SetProperties(nodeID: node, properties: ["common.name": .string(name)]))
    }

    /// Deletes the directory.
    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }
}
