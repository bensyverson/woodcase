//
//  ActivityChangeSummaryTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
import Woodcase

/// Pins ``ActivityChangeSummary``: an activity row read as old → new, from its forward
/// operations and their inverses, with one line per change.
struct ActivityChangeSummaryTests {
    private static let file = URL(fileURLWithPath: "/Users/agent/Designs/demo.pen")
    private static let titleID = "jSUCH"

    private static func event(
        op: ActivityEvent.Kind,
        nodes: [String] = [],
        paths: [String] = [],
        forward: [EditOperation],
        inverse: [EditOperation]
    ) -> ActivityEvent {
        ActivityEvent(
            time: Date(timeIntervalSince1970: 1_788_000_000),
            identity: "ben",
            file: file,
            op: op,
            nodes: nodes,
            paths: paths,
            inverse: inverse,
            forward: forward,
            revision: "0123456789abcdef",
            batch: "B1"
        )
    }

    private static func node(_ json: String) throws -> PenNode {
        try JSONDecoder().decode(PenNode.self, from: Data(json.utf8))
    }

    /// One key of an object value, or `nil` when the value is not an object.
    private static func field(_ value: AnyCodable?, _ key: String) -> AnyCodable? {
        guard case let .dictionary(object) = value else { return nil }
        return object[key]
    }

    // MARK: - Whole-struct updates

    @Test("A recorded whole-struct updateCommon yields only the key it changed, old and new")
    func recordedUpdateCommonYieldsChangedKeyOnly() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ActivityChangeSummaryTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = try #require(Bundle.module.url(
            forResource: "layout-vertical", withExtension: "pen", subdirectory: "Fixtures"
        ))
        let url = directory.appendingPathComponent("layout-vertical.pen")
        try FileManager.default.copyItem(at: source, to: url)
        let log = ActivityLog(home: directory.appendingPathComponent("home"))

        try await PenFileTransaction.run(at: url, identity: "ben", log: log) { document, recorder in
            var node = try #require(document.nodes[Self.titleID])
            node.common.name = "Title"
            try recorder.apply(.updateCommon(EditOperation.UpdateCommon(nodeID: Self.titleID, common: node.common)))
        }
        let event = try #require(ActivityReader(log: log).read().events.last)

        let summary = ActivityChangeSummary(event)

        #expect(summary.identity == "ben")
        #expect(summary.op == .set)
        #expect(summary.changes == [
            ActivityChangeSummary.Change(
                kind: .set, node: Self.titleID, path: "layout-vertical/Title",
                key: "common.name", old: "child-1", new: "Title"
            ),
        ])
    }

    @Test("A whole-struct updateCommon paired with a whole-struct inverse is diffed to its changed keys")
    func wholeInverseIsDiffed() {
        let before = PenNodeCommon(name: "Title", opacity: .literal(1))
        let after = PenNodeCommon(name: "Title", opacity: .literal(0.5))
        let summary = ActivityChangeSummary(Self.event(
            op: .set, nodes: [Self.titleID], paths: ["Home/Title"],
            forward: [.updateCommon(EditOperation.UpdateCommon(nodeID: Self.titleID, common: after))],
            inverse: [.updateCommon(EditOperation.UpdateCommon(nodeID: Self.titleID, common: before))]
        ))

        #expect(summary.changes.map(\.key) == ["common.opacity"])
        #expect(summary.changes.first?.old == 1)
        #expect(summary.changes.first?.new == 0.5)
    }

    @Test("A property write reads as path, key, old and new on one line")
    func propertyLine() {
        let summary = ActivityChangeSummary(Self.event(
            op: .set, nodes: [Self.titleID], paths: ["Home/Hero/Title"],
            forward: [.setProperties(EditOperation.SetProperties(
                nodeID: Self.titleID, properties: ["kind.content": "Welcome back"]
            ))],
            inverse: [.setProperties(EditOperation.SetProperties(
                nodeID: Self.titleID, properties: ["kind.content": "Welcome"]
            ))]
        ))

        #expect(summary.changes.map(\.line) == [
            #"Home/Hero/Title  kind.content: "Welcome" → "Welcome back""#,
        ])
    }

    @Test("A property written to the value it already had is no change")
    func unchangedPropertyIsDropped() {
        let summary = ActivityChangeSummary(Self.event(
            op: .set, nodes: [Self.titleID], paths: ["Home/Title"],
            forward: [.setProperties(EditOperation.SetProperties(
                nodeID: Self.titleID, properties: ["kind.width": 100, "kind.height": 80]
            ))],
            inverse: [
                .setProperties(EditOperation.SetProperties(nodeID: Self.titleID, properties: ["kind.height": 60])),
                .setProperties(EditOperation.SetProperties(nodeID: Self.titleID, properties: ["kind.width": 100])),
            ]
        ))

        #expect(summary.changes.map(\.line) == ["Home/Title  kind.height: 60 → 80"])
    }

    @Test("A nudge reads as place, one line per coordinate")
    func placeLines() {
        let summary = ActivityChangeSummary(Self.event(
            op: .place, nodes: [Self.titleID], paths: ["Home/Title"],
            forward: [.setProperties(EditOperation.SetProperties(
                nodeID: Self.titleID, properties: ["common.x": 40, "common.y": 12]
            ))],
            inverse: [
                .setProperties(EditOperation.SetProperties(nodeID: Self.titleID, properties: ["common.x": 10])),
                .setProperties(EditOperation.SetProperties(nodeID: Self.titleID, properties: ["common.y": 12.5])),
            ]
        ))

        #expect(summary.changes.map(\.kind) == [.place, .place])
        #expect(summary.changes.map(\.line) == [
            "Home/Title  common.x: 10 → 40",
            "Home/Title  common.y: 12.5 → 12",
        ])
    }

    // MARK: - Structure

    @Test("An insert reads as added, with its type, its text and where it went")
    func addLine() throws {
        let note = try Self.node(#"{"id":"Nt001","type":"text","name":"Note","content":"Warmer, please"}"#)
        let summary = ActivityChangeSummary(Self.event(
            op: .add, nodes: ["Nt001", "Hm001"], paths: ["Home/Note", "Home"],
            forward: [.insertNode(EditOperation.InsertNode(node: note, parentID: "Hm001", index: 2))],
            inverse: [.deleteNode(EditOperation.DeleteNode(nodeID: "Nt001"))]
        ))

        let change = try #require(summary.changes.first)
        #expect(summary.changes.count == 1)
        #expect(change.kind == .add)
        #expect(change.node == "Nt001")
        #expect(change.parent == "Home")
        #expect(change.index == 2)
        #expect(change.old == nil)
        #expect(Self.field(change.new, "content") == "Warmer, please")
        #expect(change.line == #"Home/Note  added text "Warmer, please" in Home at 2"#)
    }

    @Test("A delete reads as removed, with what it was and where it was")
    func removeLine() throws {
        let badge = try Self.node(#"{"id":"Bd001","type":"frame","name":"Badge"}"#)
        let summary = ActivityChangeSummary(Self.event(
            op: .rm, nodes: ["Bd001"], paths: ["Home/Badge"],
            forward: [.deleteNode(EditOperation.DeleteNode(nodeID: "Bd001"))],
            inverse: [.insertNode(EditOperation.InsertNode(node: badge, parentID: "Hm001", index: 0))]
        ))

        let change = try #require(summary.changes.first)
        #expect(change.kind == .rm)
        #expect(change.new == nil)
        #expect(Self.field(change.old, "name") == "Badge")
        #expect(change.line == #"Home/Badge  removed frame "Badge" from Hm001 at 0"#)
    }

    @Test("A move reads as moved, from where to where")
    func moveLine() {
        let summary = ActivityChangeSummary(Self.event(
            op: .mv, nodes: [Self.titleID, "Ft001"], paths: ["Home/Footer/Title", "Home/Footer"],
            forward: [.moveNode(EditOperation.MoveNode(nodeID: Self.titleID, newParentID: "Ft001", index: 0))],
            inverse: [.moveNode(EditOperation.MoveNode(nodeID: Self.titleID, newParentID: "Hr001", index: 3))]
        ))

        #expect(summary.changes.map(\.kind) == [.mv])
        #expect(summary.changes.map(\.line) == ["Home/Footer/Title  moved from Hr001 at 3 to Home/Footer at 0"])
    }

    @Test("A move to the document root names the document")
    func moveToRootLine() {
        let summary = ActivityChangeSummary(Self.event(
            op: .mv, nodes: [Self.titleID], paths: ["Title"],
            forward: [.moveNode(EditOperation.MoveNode(nodeID: Self.titleID, newParentID: nil, index: 1))],
            inverse: [.moveNode(EditOperation.MoveNode(nodeID: Self.titleID, newParentID: "Hm001", index: 0))]
        ))

        #expect(summary.changes.map(\.line) == ["Title  moved from Hm001 at 0 to the document at 1"])
    }

    // MARK: - Components

    @Test("A descendant override reads as override, one line per key, old and new")
    func overrideLines() {
        let summary = ActivityChangeSummary(Self.event(
            op: .override, nodes: ["Cd001"], paths: ["Home/Card"],
            forward: [.overrideDescendant(EditOperation.OverrideDescendant(
                refNodeID: "Cd001", descendantID: "Tt001",
                properties: ["content": "Sale"], unset: ["fill"]
            ))],
            inverse: [
                .overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: "Cd001", descendantID: "Tt001", properties: [:], unset: ["content"]
                )),
                .overrideDescendant(EditOperation.OverrideDescendant(
                    refNodeID: "Cd001", descendantID: "Tt001", properties: ["fill": "#FF0000"]
                )),
            ]
        ))

        #expect(summary.changes.map(\.kind) == [.override, .override])
        #expect(summary.changes.map(\.descendant) == ["Tt001", "Tt001"])
        #expect(summary.changes.map(\.line) == [
            #"Home/Card  override Tt001 content: (none) → "Sale""#,
            ##"Home/Card  override Tt001 fill: "#FF0000" → (removed)"##,
        ])
    }

    @Test("A root override reads as override with no descendant")
    func rootOverrideLine() {
        let summary = ActivityChangeSummary(Self.event(
            op: .override, nodes: ["Cd001"], paths: ["Home/Card"],
            forward: [.overrideRoot(EditOperation.OverrideRoot(refNodeID: "Cd001", properties: ["width": 320]))],
            inverse: [.overrideRoot(EditOperation.OverrideRoot(refNodeID: "Cd001", properties: [:], unset: ["width"]))]
        ))

        #expect(summary.changes.map(\.line) == ["Home/Card  override width: (none) → 320"])
    }

    @Test("A detach reads as detached")
    func detachLine() {
        let summary = ActivityChangeSummary(Self.event(
            op: .detach, nodes: ["Cd001"], paths: ["Home/Card"],
            forward: [.detachRef(EditOperation.DetachRef(refNodeID: "Cd001"))],
            inverse: []
        ))

        #expect(summary.changes.map(\.line) == ["Home/Card  detached from its component"])
    }

    // MARK: - Document-level edits

    @Test("Variables read as var, by name, with the value before and after")
    func variableLines() {
        let color = { (hex: String) in PenVariable(type: .color, value: .simple(.string(hex))) }
        let added = ActivityChangeSummary(Self.event(
            op: .var,
            forward: [.addVariable(EditOperation.AddVariable(name: "--accent", variable: color("#FF8800")))],
            inverse: [.removeVariable(EditOperation.RemoveVariable(name: "--accent"))]
        ))
        let updated = ActivityChangeSummary(Self.event(
            op: .var,
            forward: [.updateVariable(EditOperation.UpdateVariable(name: "--accent", variable: color("#FF0000")))],
            inverse: [.updateVariable(EditOperation.UpdateVariable(name: "--accent", variable: color("#FF8800")))]
        ))
        let removed = ActivityChangeSummary(Self.event(
            op: .var,
            forward: [.removeVariable(EditOperation.RemoveVariable(name: "--accent"))],
            inverse: [.addVariable(EditOperation.AddVariable(name: "--accent", variable: color("#FF0000")))]
        ))

        #expect(added.changes.map(\.line) == [##"var --accent: (none) → "#FF8800""##])
        #expect(updated.changes.map(\.line) == [##"var --accent: "#FF8800" → "#FF0000""##])
        #expect(removed.changes.map(\.line) == [##"var --accent: "#FF0000" → (removed)"##])
        #expect(updated.changes.first?.key == "--accent")
        #expect(updated.changes.first?.node == nil)
    }

    @Test("Imports and theme axes read by their names")
    func importAndThemeLines() {
        let imported = ActivityChangeSummary(Self.event(
            op: .import,
            forward: [.updateImport(EditOperation.UpdateImport(alias: "ui", path: "kit-2.pen"))],
            inverse: [.updateImport(EditOperation.UpdateImport(alias: "ui", path: "kit.pen"))]
        ))
        let themed = ActivityChangeSummary(Self.event(
            op: .theme,
            forward: [.addThemeAxis(EditOperation.AddThemeAxis(name: "mode", options: ["light", "dark"]))],
            inverse: [.removeThemeAxis(EditOperation.RemoveThemeAxis(name: "mode"))]
        ))

        #expect(imported.changes.map(\.line) == [#"import ui: "kit.pen" → "kit-2.pen""#])
        #expect(themed.changes.map(\.line) == [#"theme mode: (none) → ["light","dark"]"#])
    }

    // MARK: - Rows with no forward

    @Test("An outside write reads as one line that says to re-read")
    func externalLine() {
        let summary = ActivityChangeSummary(Self.event(op: .external, forward: [], inverse: []))

        #expect(summary.changes.map(\.kind) == [.external])
        #expect(summary.changes.map(\.line) == ["changed outside woodcase — re-read the file"])
    }

    @Test("A row logged before forward existed still has a line, naming its path")
    func legacyRowHasALine() {
        let summary = ActivityChangeSummary(Self.event(
            op: .set, nodes: [Self.titleID], paths: ["Home/Title"], forward: [], inverse: []
        ))

        #expect(summary.changes.map(\.line) == ["Home/Title"])
    }

    @Test("A summary writes its time the way the log does, as an ISO-8601 string")
    func timeIsWireTime() throws {
        let summary = ActivityChangeSummary(Self.event(op: .external, forward: [], inverse: []))

        let data = try JSONEncoder().encode(summary)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["time"] as? String == "2026-08-29T10:40:00.000Z")
        #expect(try JSONDecoder().decode(ActivityChangeSummary.self, from: data) == summary)
    }

    @Test("A summary round-trips through JSON")
    func roundTrips() throws {
        let summary = ActivityChangeSummary(Self.event(
            op: .set, nodes: [Self.titleID], paths: ["Home/Title"],
            forward: [.setProperties(EditOperation.SetProperties(nodeID: Self.titleID, properties: ["kind.width": 120]))],
            inverse: [.setProperties(EditOperation.SetProperties(nodeID: Self.titleID, properties: ["kind.width": 100]))]
        ))

        #expect(summary.changes.map(\.new) == [120])
        let data = try JSONEncoder().encode(summary)
        #expect(try JSONDecoder().decode(ActivityChangeSummary.self, from: data) == summary)
    }
}
