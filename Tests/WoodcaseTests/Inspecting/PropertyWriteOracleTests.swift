//
//  PropertyWriteOracleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The single-path write produces exactly what the old whole-payload write produced:
/// every path, on every node of every bundled fixture, with the node's own value, a
/// clear, values other nodes hold at that path, and values of every JSON shape — nodes
/// and refusals alike.
///
/// The old implementation lives on here as ``Oracle``, unchanged: it encodes the whole
/// `common` or `kind` payload to a JSON dictionary, replaces one key and decodes the
/// dictionary back.
struct PropertyWriteOracleTests {
    /// What a write answered: the patched node, or the error it threw.
    enum Outcome: Equatable {
        case node(PenNode)
        case editing(EditingError)
        case other(String)

        init(_ body: () throws -> PenNode) {
            do { self = try .node(body()) } catch let error as EditingError {
                self = .editing(error)
            } catch {
                self = .other(String(describing: error))
            }
        }
    }

    /// The write as it was before a single path cost only that path.
    enum Oracle {
        /// `NodePropertyCodec.setting(_:at:on:)` as it wrote before.
        static func setting(_ value: AnyCodable, at path: String, on node: PenNode) throws -> PenNode {
            if NodePropertyCodec.isExtrasPath(path) {
                return try NodePropertyCodec.settingExtra(value, at: path, on: node)
            }
            let written = NodePropertyCodec.coercing(value, at: path, on: node.kind)
            var patched = node
            if path.hasPrefix(NodePropertyCodec.commonPrefix) {
                guard NodePropertyCodec.commonPaths.contains(path) else {
                    throw NodePropertyCodec.unknownProperty(path, node.id, node.kind.typeName)
                }
                let field = String(path.dropFirst(NodePropertyCodec.commonPrefix.count))
                let dictionary = try NodePropertyCodec.patching(
                    NodePropertyCodec.dictionary(from: node.common), field: field, value: written
                )
                do {
                    patched.common = try NodePropertyCodec.decode(PenNodeCommon.self, from: dictionary)
                } catch {
                    throw NodePropertyCodec.mismatch(path, field, written, node.id, error)
                }
            } else if path.hasPrefix(NodePropertyCodec.kindPrefix) {
                let field = try NodePropertyCodec.kindField(of: path, in: node.kind, nodeID: node.id)
                switch node.kind {
                case .ref, .unknown:
                    // These two never went through the payload dictionary.
                    patched.kind = try NodePropertyCodec.setting(written, at: path, on: node.kind, nodeID: node.id)
                default:
                    let dictionary = try NodePropertyCodec.patching(
                        NodePropertyCodec.kindDictionary(node.kind), field: field, value: written
                    )
                    do {
                        patched.kind = try NodePropertyCodec.makeKind(like: node.kind, from: dictionary)
                    } catch {
                        throw NodePropertyCodec.mismatch(path, field, written, node.id, error)
                    }
                }
            } else {
                throw NodePropertyCodec.unknownProperty(path, node.id, node.kind.typeName)
            }
            return patched
        }
    }

    /// Values of every JSON shape, valid somewhere and refused elsewhere.
    private static let shapes: [AnyCodable] = [
        .null, .int(42), .double(-1.5), .string("hello"), .string("$color.primary"), .bool(false),
        .array([]), .array([.int(1), .int(2), .int(3), .int(4)]),
        .array([.dictionary(["type": .string("nope")])]),
        .dictionary([:]), .dictionary(["type": .string("solid"), "color": .string("#336699")]),
        .dictionary(["type": .string("component")]),
    ]

    /// Paths no node takes, or that only another type takes, or deep keys — each must
    /// refuse the same way it did.
    private static let strayPaths: [String] = [
        "", "nope", "kind.", "common.", "kind.nope", "common.nope", "kind.type", "kind.children",
        "extras.nope", "common.metadata.woodcase.locked", "common.metadata.nope.deep",
    ] + NodePropertyCodec.allKindPaths.sorted()

    /// Every bundled `.pen` fixture.
    private static let fixtureFiles: [URL] = {
        guard let root = Bundle.module.url(forResource: "Fixtures", withExtension: nil),
              let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)
        else { return [] }
        return files.compactMap { $0 as? URL }
            .filter { $0.pathExtension == "pen" }
            .sorted { $0.path < $1.path }
    }()

    /// Every node of one fixture, or none when it does not parse.
    private static func nodes(in file: URL) -> [PenNode] {
        guard let document = try? PenParser.parse(contentsOf: file) else { return [] }
        var nodes: [PenNode] = []
        var stack = Array(document.children.reversed())
        while let node = stack.popLast() {
            nodes.append(node)
            stack.append(contentsOf: (node.kind.inlineChildrenIfPresent ?? []).reversed())
        }
        return nodes
    }

    /// Up to three distinct values the fixtures hold at each path — real fills, paddings
    /// and effects to write onto other nodes, including nodes of other types.
    private static let pool: [String: [AnyCodable]] = {
        var pool: [String: [AnyCodable]] = [:]
        for file in fixtureFiles {
            for node in nodes(in: file) {
                for path in NodePropertyCodec.paths(for: node) {
                    guard let value = try? NodePropertyCodec.value(at: path, of: node), value != .null,
                          pool[path, default: []].count < 3, !pool[path, default: []].contains(value)
                    else { continue }
                    pool[path, default: []].append(value)
                }
            }
        }
        return pool
    }()

    /// The node with its inline `children` absent: no path writes them, and old writes
    /// encode the whole subtree, which would make the full matrix quadratic in depth.
    /// ``childrenSurviveWrites(file:)`` covers the subtree itself.
    private static func strippingChildren(_ node: PenNode) -> PenNode {
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

    @Test("The fixtures cover every node type, and the pool covers every path")
    func fixturesCoverEveryType() {
        let nodes = Self.fixtureFiles.flatMap(Self.nodes(in:))
        #expect(Set(nodes.compactMap(\.kind.nodeType)) == Set(PenNode.NodeType.allCases))
        #expect(nodes.contains { if case .unknown = $0.kind { true } else { false } })
        #expect(Self.pool.count > 60)
    }

    @Test("Every path writes the same on every node of a fixture", arguments: fixtureFiles)
    func writesMatchOracle(file: URL) {
        for (nodeIndex, original) in Self.nodes(in: file).enumerated() {
            let node = Self.strippingChildren(original)
            for (pathIndex, path) in (NodePropertyCodec.paths(for: node) + Self.strayPaths).enumerated() {
                let pooled = Self.pool[path] ?? []
                var values: [AnyCodable] = [.null, (try? NodePropertyCodec.value(at: path, of: node)) ?? .null]
                if !pooled.isEmpty { values.append(pooled[nodeIndex % pooled.count]) }
                values.append(Self.shapes[(nodeIndex + pathIndex) % Self.shapes.count])
                values.append(Self.shapes[(nodeIndex + 2 * pathIndex + 5) % Self.shapes.count])
                for value in values {
                    let expected = Outcome { try Oracle.setting(value, at: path, on: node) }
                    let actual = Outcome { try NodePropertyCodec.setting(value, at: path, on: node) }
                    #expect(actual == expected, "\(file.lastPathComponent) \(node.id) \(path) = \(value)")
                }
            }
        }
    }

    @Test("A refusal names the same fault however the value's keys happen to be ordered")
    func refusalIsDeterministic() {
        let instance = PenNode(id: "inst", common: PenNodeCommon(), kind: .ref(PenNode.RefData(ref: "Card")))
        let keys = ["color", "type", "width", "fill", "enabled", "name", "x", "y"]
        var refusals: Set<String> = []
        for capacity in [0, 4, 16, 64, 256] {
            for rotation in keys.indices {
                var value = [String: AnyCodable](minimumCapacity: capacity)
                for key in keys[rotation...] + keys[..<rotation] {
                    value[key] = .string("bad")
                }
                let outcome = Outcome {
                    try NodePropertyCodec.setting(.dictionary(value), at: "kind.descendants", on: instance)
                }
                refusals.insert(String(describing: outcome))
            }
        }
        #expect(refusals.count == 1, "\(refusals)")
    }

    @Test("A write to a container keeps its subtree exactly", arguments: fixtureFiles)
    func childrenSurviveWrites(file: URL) {
        for node in Self.nodes(in: file) where !(node.kind.inlineChildrenIfPresent ?? []).isEmpty {
            for path in ["kind.width", "kind.layout", "common.name", "common.metadata"] {
                for value in [AnyCodable.null, .int(321), .string("vertical"), .string("Renamed")] {
                    let expected = Outcome { try Oracle.setting(value, at: path, on: node) }
                    let actual = Outcome { try NodePropertyCodec.setting(value, at: path, on: node) }
                    #expect(actual == expected, "\(file.lastPathComponent) \(node.id) \(path) = \(value)")
                }
            }
        }
    }
}
