//
//  NodePropertyBatchTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A batch write (``NodePropertyCodec/setting(_:on:)``) gives exactly what writing its keys
/// one at a time (``NodePropertyCodec/setting(_:at:on:)``) gives, in the dictionary's own
/// order — the node, or the refusal and the key it names — on every node of every bundled
/// fixture, for whole-vocabulary maps, scale-shaped maps, maps holding a bad key or value,
/// and maps whose keys store into the same place.
struct NodePropertyBatchTests {
    typealias Outcome = PropertyWriteOracleTests.Outcome

    /// The per-key writes a batch must equal, in `properties`' own iteration order.
    static func sequential(_ properties: [String: AnyCodable], on node: PenNode) throws -> PenNode {
        try properties.reduce(node) { try NodePropertyCodec.setting($1.value, at: $1.key, on: $0) }
    }

    /// The same entries in dictionaries of several capacities, so they iterate in
    /// several orders.
    static func orderings(of entries: [(String, AnyCodable)]) -> [[String: AnyCodable]] {
        [0, 64].flatMap { capacity in
            [entries, entries.reversed()].map { list in
                var map = [String: AnyCodable](minimumCapacity: capacity)
                for (key, value) in list {
                    map[key] = value
                }
                return map
            }
        }
    }

    /// Requires the batch to match the per-key writes on every ordering of `entries`.
    static func expectEquivalent(
        _ entries: [(String, AnyCodable)], on node: PenNode, _ comment: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        for map in orderings(of: entries) {
            let expected = Outcome { try sequential(map, on: node) }
            let actual = Outcome { try NodePropertyCodec.setting(map, on: node) }
            #expect(actual == expected, "\(comment) \(Array(map.keys))", sourceLocation: sourceLocation)
        }
    }

    /// One node of every shape the bundled fixtures hold, children stripped: the
    /// first node of each type with each set of properties set. Every node would cost a
    /// minute on the big fixtures and cover nothing more — a batch's outcome turns on which
    /// keys a node holds, not on their values.
    static let fixtureNodes: [(file: String, node: PenNode)] = {
        guard let root = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
              let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        let urls = files.compactMap { $0 as? URL }.filter { $0.pathExtension == "pen" }.sorted { $0.path < $1.path }
        var nodes: [(String, PenNode)] = []
        var shapes: Set<[String]> = []
        for url in urls {
            guard let document = try? PenParser.parse(contentsOf: url) else { continue }
            var stack = Array(document.children.reversed())
            while let node = stack.popLast() {
                let stripped = strippingChildren(node)
                let held = NodePropertyCodec.paths(for: stripped).filter {
                    ((try? NodePropertyCodec.value(at: $0, of: stripped)) ?? .null) != .null
                }
                if shapes.insert([stripped.kind.typeName] + held).inserted {
                    nodes.append((url.lastPathComponent, stripped))
                }
                stack.append(contentsOf: (node.kind.inlineChildrenIfPresent ?? []).reversed())
            }
        }
        return nodes
    }()

    /// The node with its inline `children` absent, which no path writes.
    static func strippingChildren(_ node: PenNode) -> PenNode {
        var stripped = node
        switch node.kind {
        case var .frame(data):
            data.children = nil
            stripped.kind = .frame(data)
        case var .group(data):
            data.children = nil
            stripped.kind = .group(data)
        default: break
        }
        return stripped
    }

    /// A number scaled by 1.5, or the value itself.
    static func scaled(_ value: AnyCodable) -> AnyCodable {
        switch value {
        case let .int(number): .double(Double(number) * 1.5)
        case let .double(number): .double(number * 1.5)
        default: value
        }
    }

    @Test("Every path written back with its own value, all at once, matches the per-key writes")
    func wholeVocabularyRoundTrip() {
        #expect(Set(Self.fixtureNodes.compactMap(\.node.kind.nodeType)) == Set(PenNode.NodeType.allCases))
        #expect(Self.fixtureNodes.contains { if case .unknown = $0.node.kind { true } else { false } })
        for (file, node) in Self.fixtureNodes {
            let entries = NodePropertyCodec.paths(for: node).map { path in
                (path, (try? NodePropertyCodec.value(at: path, of: node)) ?? .null)
            }
            Self.expectEquivalent(entries, on: node, "\(file) \(node.id) own values")
        }
    }

    @Test("A scale's keys — positions, sizes, type, strokes, radii, gaps, paddings, effects — match")
    func scaleShapedPatch() {
        let scaleKeys = [
            "common.x", "common.y", "kind.width", "kind.height", "kind.fontSize", "kind.letterSpacing",
            "kind.strokeWidth", "kind.cornerRadius", "kind.gap", "kind.padding", "kind.effects",
            "kind.lineHeight", "common.rotation",
        ]
        for (file, node) in Self.fixtureNodes {
            let paths = Set(NodePropertyCodec.paths(for: node))
            let entries = scaleKeys.filter(paths.contains).map { path in
                (path, Self.scaled((try? NodePropertyCodec.value(at: path, of: node)) ?? .null))
            }
            Self.expectEquivalent(entries, on: node, "\(file) \(node.id) scaled")
        }
    }

    @Test("Values of every shape, cleared keys and paths the node does not take refuse or write the same")
    func mixedAndRefused() {
        let shapes: [AnyCodable] = [
            .null, .int(42), .double(-1.5), .string("hello"), .string("$color.primary"), .bool(false),
            .array([.int(1), .int(2)]), .dictionary(["type": .string("solid"), "color": .string("#336699")]),
        ]
        let strays = ["kind.nope", "common.nope", "nope", "kind.type", "extras.nope", "common.metadata.nope.deep"]
        for (index, (file, node)) in Self.fixtureNodes.enumerated() {
            let paths = NodePropertyCodec.paths(for: node)
            guard !paths.isEmpty else { continue }
            for round in 0 ..< 4 {
                var entries: [(String, AnyCodable)] = []
                for offset in 0 ..< 5 {
                    let path = paths[(index * 7 + round * 5 + offset * 3) % paths.count]
                    guard !entries.contains(where: { $0.0 == path }) else { continue }
                    entries.append((path, shapes[(index + round + offset) % shapes.count]))
                }
                if round == 3 { entries.append((strays[index % strays.count], .int(1))) }
                Self.expectEquivalent(entries, on: node, "\(file) \(node.id) round \(round)")
            }
        }
    }

    @Test("Keys that store into the same place land in the per-key order")
    func sharedStorage() {
        let note = PenNode(
            id: "n", common: PenNodeCommon(x: .literal(1)),
            kind: .note(PenNode.NoteData(content: .literal("Hi")))
        )
        let card = PenNode(
            id: "c", common: PenNodeCommon(name: "Card"),
            kind: .frame(PenNode.FrameData(width: .fixed(100)))
        )
        let shadow: AnyCodable = .array([.dictionary([
            "type": .string("shadow"), "shadowType": .string("outer"), "blur": .int(4), "spread": .int(3),
            "color": .string("#00000040"),
        ])])
        let metadata: AnyCodable = .dictionary([
            "type": .string("woodcase"), "woodcase": .dictionary(["fontSize": .int(30), "role": .string("button")]),
        ])
        Self.expectEquivalent(
            [("note.fontSize", .int(20)), ("common.metadata", metadata), ("common.x", .int(9))],
            on: note, "note alias and its raw metadata"
        )
        Self.expectEquivalent(
            [("kind.effects", shadow), ("common.metadata", metadata), ("kind.width", .int(50)), ("common.name", .string("B"))],
            on: card, "named spread and metadata"
        )
        Self.expectEquivalent(
            [("codegen.role", .string("link")), ("codegen.props.label", .string("Go")),
             ("common.metadata", metadata), ("common.locked", .bool(true)), ("kind.width", .int(5))],
            on: card, "codegen paths, a natural common path and metadata"
        )
        Self.expectEquivalent(
            [("extras.future", .int(1)), ("kind.width", .int(5)), ("kind.height", .string("bad"))],
            on: card, "an extra beside a refused value"
        )
    }

    @Test("A refusal names the same key as the per-key writes")
    func refusalNamesTheSameKey() {
        let card = PenNode(id: "c", common: PenNodeCommon(), kind: .frame(PenNode.FrameData(width: .fixed(100))))
        let entries: [(String, AnyCodable)] = [
            ("kind.width", .string("wide")), ("common.x", .string("left")), ("kind.gap", .int(4)), ("common.y", .int(2)),
        ]
        for map in Self.orderings(of: entries) {
            #expect(throws: (any Error).self) { try NodePropertyCodec.setting(map, on: card) }
            let expected = Outcome { try Self.sequential(map, on: card) }
            #expect(Outcome { try NodePropertyCodec.setting(map, on: card) } == expected)
        }
    }
}
