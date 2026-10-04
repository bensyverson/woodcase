//
//  ActivityForwardTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins the `forward` field of ``ActivityEvent``: the operation as applied, recorded
/// beside its inverse so a feed can show old and new values without reconstructing them.
struct ActivityForwardTests {
    private static let file = URL(fileURLWithPath: "/Users/agent/Designs/demo.pen")
    private static let fixtureName = "layout-vertical.pen"
    private static let targetNodeID = "jSUCH"

    private static let forward: [EditOperation] = [
        .setProperties(EditOperation.SetProperties(
            nodeID: "jSUCH",
            properties: ["kind.width": .int(320)]
        )),
    ]

    private static func event(forward: [EditOperation]) -> ActivityEvent {
        ActivityEvent(
            time: Date(timeIntervalSince1970: 1_788_000_000.123),
            identity: "logger",
            file: file,
            op: .set,
            nodes: ["jSUCH"],
            paths: ["layout-vertical/child-1"],
            inverse: [],
            forward: forward,
            revision: "0123456789abcdef"
        )
    }

    // MARK: - Wire format

    @Test("A forward operation survives a round trip through its line")
    func forwardRoundTrips() throws {
        let original = Self.event(forward: Self.forward)
        let line = try original.jsonLine()
        #expect(String(decoding: line, as: UTF8.self).contains("\"forward\":["))
        #expect(try ActivityEvent(line: line) == original)
    }

    @Test("A line written before forward existed decodes with an empty forward")
    func oldLinesDecodeWithEmptyForward() throws {
        let old = """
        {"file":"/Users/agent/Designs/demo.pen","identity":"logger","inverse":[],\
        "nodes":["jSUCH"],"op":"set","paths":["layout-vertical/child-1"],\
        "revision":"0123456789abcdef","time":"2026-08-29T16:31:04.123Z"}
        """
        let decoded = try ActivityEvent(line: Data(old.utf8))
        #expect(decoded.forward.isEmpty)
    }

    @Test("An event with no forward omits the key, so old and new bytes agree")
    func emptyForwardIsOmitted() throws {
        let line = try String(decoding: Self.event(forward: []).jsonLine(), as: UTF8.self)
        #expect(!line.contains("forward"))
    }

    // MARK: - Recording

    private func withFixtureAndLog<T>(
        _ body: (URL, ActivityLog) async throws -> T
    ) async throws -> T {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityForwardTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try #require(Bundle.module.url(
            forResource: "layout-vertical", withExtension: "pen", subdirectory: "Fixtures"
        ))
        let url = directory.appendingPathComponent(Self.fixtureName)
        try FileManager.default.copyItem(at: source, to: url)
        return try await body(url, ActivityLog(home: directory.appendingPathComponent("home")))
    }

    @Test("Every recorded row carries the operation that was applied, and reads back")
    func recordedRowsRoundTripForward() async throws {
        try await withFixtureAndLog { url, log in
            let operations: [EditOperation] = try await PenFileTransaction.run(
                at: url, identity: "logger", log: log
            ) { document, recorder in
                var node = try #require(document.nodes[Self.targetNodeID])
                node.common.name = "renamed"
                let rename = EditOperation.updateCommon(
                    EditOperation.UpdateCommon(nodeID: Self.targetNodeID, common: node.common)
                )
                let axis = EditOperation.addThemeAxis(
                    EditOperation.AddThemeAxis(name: "mode", options: ["light", "dark"])
                )
                try recorder.apply(rename)
                try recorder.apply(axis)
                #expect(recorder.events.map(\.forward) == [[rename], [axis]])
                return [rename, axis]
            }.value

            let events = try ActivityReader(log: log).read().events
            #expect(events.map(\.forward) == operations.map { [$0] })
        }
    }
}
