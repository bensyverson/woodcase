//
//  ActivityEventTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins ``ActivityEvent``'s wire format: one JSON object per line, sorted keys,
/// unescaped slashes, and an ISO-8601 UTC timestamp with milliseconds.
///
/// The golden line below is the contract other tools read. Changing it is a
/// format change, not a test fix.
struct ActivityEventTests {
    // MARK: - Fixtures

    /// A file path chosen to contain no symlinked component on any platform, so
    /// ``ActivityEvent/canonicalPath(for:)`` leaves it alone and the golden line
    /// is stable.
    private static let file = URL(fileURLWithPath: "/Users/agent/Designs/demo.pen")

    private static let inverse: [EditOperation] = [
        .setProperties(EditOperation.SetProperties(
            nodeID: "jSUCH",
            properties: ["kind.width": .int(240)]
        )),
    ]

    private static func sampleEvent() throws -> ActivityEvent {
        try ActivityEvent(
            time: Date("2026-08-29T16:31:04.123Z", strategy: ActivityEvent.timeFormat),
            identity: "logger",
            file: file,
            op: .set,
            nodes: ["jSUCH"],
            paths: ["layout-vertical/child-1"],
            inverse: inverse,
            revision: "0123456789abcdef",
            batch: "b1"
        )
    }

    private static let goldenLine = """
    {"batch":"b1","file":"/Users/agent/Designs/demo.pen","identity":"logger",\
    "inverse":[{"setProperties":{"_0":{"nodeID":"jSUCH","properties":{"kind.width":240}}}}],\
    "nodes":["jSUCH"],"op":"set","paths":["layout-vertical/child-1"],\
    "revision":"0123456789abcdef","time":"2026-08-29T16:31:04.123Z"}
    """

    // MARK: - Wire format

    @Test("A set event encodes to its golden JSONL line")
    func setEventEncodesToTheGoldenLine() throws {
        let line = try Self.sampleEvent().jsonLine()
        #expect(String(decoding: line, as: UTF8.self) == Self.goldenLine)
    }

    @Test("The golden line decodes back to an equal event")
    func goldenLineDecodesToAnEqualEvent() throws {
        let decoded = try ActivityEvent(line: Data(Self.goldenLine.utf8))
        let expected = try Self.sampleEvent()
        #expect(decoded == expected)
    }

    @Test("An event with no batch omits the key entirely")
    func eventWithoutABatchOmitsTheKey() throws {
        var event = try Self.sampleEvent()
        event.batch = nil
        let line = try String(decoding: event.jsonLine(), as: UTF8.self)
        let decoded = try ActivityEvent(line: Data(line.utf8))
        #expect(!line.contains("batch"))
        #expect(decoded == event)
    }

    @Test("Times are held to millisecond precision so a line round-trips exactly")
    func timeIsTruncatedToMilliseconds() throws {
        let event = ActivityEvent(
            time: Date(timeIntervalSince1970: 1_756_484_664.1234567),
            identity: "logger",
            file: Self.file,
            op: .add,
            revision: "abc"
        )
        let round = try ActivityEvent(line: event.jsonLine())
        #expect(round == event)
        #expect(round.time.timeIntervalSince1970 == 1_756_484_664.123)
    }

    @Test("A line never contains a raw newline, so one event is one line")
    func linesAreSingleLines() throws {
        let event = ActivityEvent(
            time: Date(),
            identity: "a\nb",
            file: Self.file,
            op: .set,
            paths: ["one\ntwo"],
            revision: "abc"
        )
        let line = try event.jsonLine()
        #expect(!line.contains(0x0A))
    }

    // MARK: - Deriving the kind

    @Test(
        "Each operation maps to its short verb",
        arguments: [
            (EditOperation.insertNode(EditOperation.InsertNode(node: PenNode(
                id: "n1", common: PenNodeCommon(), kind: .group(PenNode.GroupData())
            ))), ActivityEvent.Kind.add),
            (.deleteNode(EditOperation.DeleteNode(nodeID: "n1")), .rm),
            (.moveNode(EditOperation.MoveNode(nodeID: "n1")), .mv),
            (.updateCommon(EditOperation.UpdateCommon(nodeID: "n1", common: PenNodeCommon())), .set),
            (.setProperties(EditOperation.SetProperties(nodeID: "n1", properties: [:])), .set),
            (.overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "r1", descendantID: "d1", properties: [:]
            )), .override),
            (.detachRef(EditOperation.DetachRef(refNodeID: "r1")), .detach),
            (.removeVariable(EditOperation.RemoveVariable(name: "brand")), .var),
            (.addImport(EditOperation.AddImport(alias: "ui", path: "./ui.pen")), .import),
            (.addThemeAxis(EditOperation.AddThemeAxis(name: "mode", options: ["light"])), .theme),
        ]
    )
    func operationsMapToKinds(operation: EditOperation, expected: ActivityEvent.Kind) {
        #expect(ActivityEvent.Kind(operation) == expected)
    }

    // MARK: - Deriving the nodes

    @Test("An insert names the new node then its parent")
    func insertNamesNodeAndParent() {
        let operation = EditOperation.insertNode(EditOperation.InsertNode(
            node: PenNode(id: "n1", common: PenNodeCommon(), kind: .group(PenNode.GroupData())),
            parentID: "p1"
        ))
        #expect(ActivityEvent.nodeIDs(touchedBy: operation) == ["n1", "p1"])
    }

    @Test("A move names the node then its new parent")
    func moveNamesNodeAndNewParent() {
        let operation = EditOperation.moveNode(
            EditOperation.MoveNode(nodeID: "n1", newParentID: "p2")
        )
        #expect(ActivityEvent.nodeIDs(touchedBy: operation) == ["n1", "p2"])
    }

    @Test("A document-scoped operation names no nodes")
    func documentScopedOperationsNameNoNodes() {
        let operation = EditOperation.addThemeAxis(
            EditOperation.AddThemeAxis(name: "mode", options: ["light", "dark"])
        )
        #expect(ActivityEvent.nodeIDs(touchedBy: operation).isEmpty)
    }
}
