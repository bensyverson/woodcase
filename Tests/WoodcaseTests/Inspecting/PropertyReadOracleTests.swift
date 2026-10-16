//
//  PropertyReadOracleTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The single-path read and the cached schema tables answer exactly what the old
/// whole-payload read and the per-call table build answered: every path, on every node
/// of every bundled fixture, and every spelling of every row on every type — values,
/// `null`s and errors alike.
///
/// The old implementations live on here as ``Oracle``, unchanged but for one thing: it
/// encodes each node's payloads once and reads every path from that, which is what the
/// old read did per path, since the payload is a pure function of the node.
struct PropertyReadOracleTests {
    /// What a read answered: a value, or the error it threw.
    enum Outcome: Equatable {
        case value(AnyCodable)
        case editing(EditingError)
        case other(String)

        init(_ body: () throws -> AnyCodable) {
            do { self = try .value(body()) } catch let error as EditingError {
                self = .editing(error)
            } catch {
                self = .other(String(describing: error))
            }
        }
    }

    /// The reads as they were before a single path cost only that path.
    enum Oracle {
        /// A node's payloads, encoded whole, once.
        struct Payloads {
            let common: [String: AnyCodable]
            let kind: [String: AnyCodable]?

            /// Encodes `node`'s payloads. Inline children are dropped first: no path
            /// reads them, and encoding every subtree once per node would make this
            /// check quadratic in the fixture's depth for no coverage.
            init(_ node: PenNode) throws {
                common = try NodePropertyCodec.dictionary(from: node.common)
                switch node.kind {
                case .ref, .unknown: kind = nil
                default: kind = try NodePropertyCodec.kindDictionary(Self.strippingChildren(node.kind))
                }
            }

            /// The kind with its `children` key absent rather than empty.
            private static func strippingChildren(_ kind: PenNode.Kind) -> PenNode.Kind {
                switch kind {
                case var .frame(data):
                    data.children = nil
                    return .frame(data)
                case var .group(data):
                    data.children = nil
                    return .group(data)
                default: return kind
                }
            }
        }

        /// `NodePropertyCodec.value(at:of:)` as it read before.
        static func value(at path: String, of node: PenNode, payloads: Payloads) throws -> AnyCodable {
            if let (property, keyPath) = NodePropertyCodec.deepKey(of: path) {
                return try NodePropertyCodec.deepValue(in: property, at: keyPath, of: node)
            }
            if path.hasPrefix("common.") {
                guard NodePropertyCodec.commonPaths.contains(path) else {
                    throw NodePropertyCodec.unknownProperty(path, node.id, node.kind.typeName)
                }
                let field = String(path.dropFirst("common.".count))
                return payloads.common[NodePropertyCodec.jsonKey(for: field)] ?? .null
            }
            if path.hasPrefix("kind.") {
                let field = try NodePropertyCodec.kindField(of: path, in: node.kind, nodeID: node.id)
                switch node.kind {
                case let .unknown(_, properties):
                    return properties[field] ?? .null
                case let .ref(data):
                    switch field {
                    case "ref": return .string(data.ref)
                    case "descendants": return try NodePropertyCodec.encode(data.descendants)
                    default: return data.rootOverrides.map { .dictionary($0) } ?? .null
                    }
                default:
                    return payloads.kind?[NodePropertyCodec.jsonKey(for: field)] ?? .null
                }
            }
            if NodePropertyCodec.isExtrasPath(path) {
                return try NodePropertyCodec.extraValue(at: path, of: node)
            }
            throw NodePropertyCodec.unknownProperty(path, node.id, node.kind.typeName)
        }

        /// `PenSchema.field(_:for:)` as it looked up before, over freshly built tables.
        static func field(_ property: String, for type: PenNode.NodeType) -> PenSchemaTable.Property? {
            if let row = PenSchema.woodcaseFields(for: type).first(where: { $0.path == property }) { return row }
            let path = NodePropertyCodec.fieldName(of: property) != nil
                ? property
                : NodePropertyCodec.path(forRawKey: property)
            guard let path else { return nil }
            if NodePropertyCodec.commonPaths.contains(path) {
                return PenSchema.buildCommonTable().properties.first { $0.path == path }
            }
            guard PropertyDiff.allKindKeys(type).contains(path) else { return nil }
            return PenSchema.buildTable(for: type).properties.first { $0.path == path }
        }
    }

    /// Paths no node takes, or that only another type takes, or deep keys — each must
    /// fail, or read `null`, the same way it did.
    private static let strayPaths: [String] = [
        "", "nope", "kind.", "common.", "kind.nope", "common.nope", "kind.type", "kind.children",
        "extras.nope", "common.metadata.woodcase.locked", "common.metadata.type",
        "common.metadata.woodcase.strokeDash", "common.metadata.nope.deep", "common.metadata.",
    ] + NodePropertyCodec.allKindPaths.sorted()

    /// Every node of every bundled `.pen` fixture that parses.
    private static func fixtureNodes() throws -> [PenNode] {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let files = try #require(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "pen" }
            .sorted { $0.path < $1.path }
        var nodes: [PenNode] = []
        func walk(_ node: PenNode) {
            nodes.append(node)
            node.kind.inlineChildrenIfPresent?.forEach(walk)
        }
        for file in files {
            guard let document = try? PenParser.parse(contentsOf: file) else { continue }
            document.children.forEach(walk)
        }
        return nodes
    }

    @Test("Every path reads the same on every fixture node")
    func valuesMatchOracle() throws {
        let nodes = try Self.fixtureNodes()
        let seen = Set(nodes.compactMap(\.kind.nodeType))
        #expect(seen == Set(PenNode.NodeType.allCases), "a node type is missing from the fixtures")
        #expect(nodes.contains { if case .unknown = $0.kind { true } else { false } })

        var compared = 0
        for node in nodes {
            let payloads = try Oracle.Payloads(node)
            for path in NodePropertyCodec.paths(for: node) + Self.strayPaths {
                let expected = Outcome { try Oracle.value(at: path, of: node, payloads: payloads) }
                let actual = Outcome { try NodePropertyCodec.value(at: path, of: node) }
                #expect(actual == expected, "\(node.kind.typeName) \(node.id) \(path)")
                compared += 1
            }
        }
        #expect(compared > 100_000)
    }

    @Test("Every spelling of every row looks up the same row", arguments: PenNode.NodeType.allCases)
    func fieldsMatchOracle(type: PenNode.NodeType) {
        let fields = NodePropertyCodec.commonPaths.union(NodePropertyCodec.allKindPaths).sorted()
        let rawKeys = fields.compactMap(NodePropertyCodec.fieldName(of:)).map(NodePropertyCodec.jsonKey(for:))
        let woodcase = PenNode.NodeType.allCases.flatMap { PenSchema.woodcaseFields(for: $0).map(\.path) }
        let stray = [
            "", "nope", "kind.nope", "common.nope", "fills", "effects", "children", "type",
            "metadata.woodcase.locked", "woodcase.locked", "common.metadata.woodcase.nope",
        ]
        for property in fields + rawKeys + woodcase + stray {
            #expect(PenSchema.field(property, for: type) == Oracle.field(property, for: type), "\(type) \(property)")
        }
    }

    /// A payload that writes one key through a nested container — a route the
    /// single-key walk does not follow.
    private struct NestedPayload: Encodable {
        enum Key: String, CodingKey { case inner, plain }
        enum InnerKey: String, CodingKey { case value }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: Key.self)
            try container.encode(7, forKey: .plain)
            var inner = container.nestedContainer(keyedBy: InnerKey.self, forKey: .inner)
            try inner.encode("deep", forKey: .value)
        }
    }

    @Test("A payload the single-key walk does not follow is read whole, the same as before")
    func unsupportedPayloadFallsBack() throws {
        let nested = NestedPayload()
        #expect(try SingleKeyEncoder.value(forKey: "plain", in: nested) == nil)
        for key in ["plain", "inner", "absent"] {
            #expect(try NodePropertyCodec.singleValue(forKey: key, in: nested)
                == NodePropertyCodec.dictionary(from: nested)[key] ?? .null)
        }

        // `AnyCodable` encodes through a single-value container.
        let object = AnyCodable.dictionary(["x": .int(1), "y": .string("two")])
        #expect(try SingleKeyEncoder.value(forKey: "x", in: object) == nil)
        #expect(try NodePropertyCodec.singleValue(forKey: "x", in: object) == .int(1))
        #expect(try NodePropertyCodec.singleValue(forKey: "z", in: object) == .null)
    }

    @Test("The cached tables are the tables a fresh build makes", arguments: PenNode.NodeType.allCases)
    func tablesMatchFreshBuild(type: PenNode.NodeType) {
        #expect(PenSchema.table(for: type) == PenSchema.buildTable(for: type))
        #expect(PenSchema.common == PenSchema.buildCommonTable())
        #expect(PropertyDiff.allKindKeys(type) == PropertyDiff.buildKindKeys(type))
    }
}
