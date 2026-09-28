//
//  PenNode.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// A single node in the .pen scene graph.
///
/// Each node has:
/// - An `id` (unique within the document, no `/` characters)
/// - Common Entity properties (``PenNodeCommon``)
/// - Type-specific data (``Kind``)
///
/// The .pen JSON format is flat — common and type-specific properties coexist at the same level.
/// The custom `Codable` implementation decodes `type` first, then delegates to `PenNodeCommon`
/// and the appropriate `*Data` struct, both reading from the same decoder.
public struct PenNode: Friendly, Identifiable {
    /// Creates a node.
    ///
    /// - Parameters:
    ///   - id: The node's id, unique within the document.
    ///   - common: The properties every node type shares.
    ///   - kind: The type-specific data.
    ///   - extras: Keys a file wrote on this node that its type does not model.
    public init(
        id: String,
        common: PenNodeCommon,
        kind: PenNode.Kind,
        extras: PenExtras = PenExtras()
    ) {
        self.id = id
        self.common = common
        self.kind = kind
        self.extras = extras
    }

    /// The node's id, unique within the document.
    public let id: String

    /// The properties every node type shares.
    public var common: PenNodeCommon

    /// The type-specific data.
    public var kind: Kind

    /// Keys the file wrote on this node that its type does not model, kept verbatim.
    ///
    /// Always empty for a `ref`, whose unclaimed keys are root overrides, and for a
    /// node of an unknown type, whose keys are all its ``Kind/unknown(typeName:properties:)``
    /// properties. See ``PenExtras``.
    public var extras: PenExtras
}

// MARK: - Kind

public extension PenNode {
    /// The type-specific data for a .pen node.
    ///
    /// `indirect` keeps the payload out of line: a node is a few hundred bytes rather
    /// than well over a kilobyte, and a debug build — which gives every temporary its
    /// own stack slot — no longer spends kilobytes per level of a recursive walk over
    /// the tree. See `project/2026-09-26-debug-stack-depth.md`.
    indirect enum Kind: Friendly {
        case frame(FrameData)
        case text(TextData)
        case rectangle(RectangleData)
        case ellipse(EllipseData)
        case path(PathData)
        case group(GroupData)
        case line(LineData)
        case polygon(PolygonData)
        case ref(RefData)
        case note(NoteData)
        case prompt(PromptData)
        case context(ContextData)
        case icon(IconData)
        case script(ScriptData)
        case browser(BrowserData)
        case connection(ConnectionData)
        case unknown(typeName: String, properties: [String: AnyCodable])
    }
}

// MARK: - Node Type Enum

public extension PenNode {
    /// Known .pen node type strings used for Codable dispatch.
    ///
    /// The cases are declared in the order a reader meets them — containers, then the
    /// drawn shapes, then text, then the nodes that carry words rather than pixels, then
    /// an instance of a reusable node, then the connector between two nodes. `allCases` is what `woodcase schema` prints, so
    /// the declaration order *is* the reading order; nothing else depends on it, because
    /// the raw values drive the `Codable` dispatch.
    enum NodeType: String, Friendly, CaseIterable {
        case frame
        case group
        case rectangle
        case ellipse
        case path
        case polygon
        case text
        case note
        case prompt
        case context
        case icon
        case script
        case browser
        case ref
        case line
        case connection
    }
}

// MARK: - PenNode + Codable

public extension PenNode {
    /// The two keys every node object has.
    internal enum CodingKeys: String, CodingKey {
        case id, type
    }

    /// Decodes a node and everything under it: each node's shared properties, its type's
    /// data, and — for a modelled type — every key that type does not claim, into
    /// ``extras``.
    ///
    /// The subtree is decoded from a work list rather than by each node decoding its
    /// children, so the decode's stack use does not grow with the tree's depth — see
    /// ``decodedTree(from:)``.
    ///
    /// - Parameter decoder: The decoder to read from. In ``PenDecodingMode/authoring`` an
    ///   unclaimed key on a modelled type is refused rather than kept.
    /// - Throws: `DecodingError` for a missing `id` or `type`, a property of the wrong
    ///   shape, or — in authoring mode — an unclaimed key or a `type` this build does not
    ///   model.
    init(from decoder: Decoder) throws {
        self = try Self.decodedTree(from: decoder)
    }

    /// Encodes the node as one flat object, extras included.
    ///
    /// - Parameter encoder: The encoder to write to.
    /// - Throws: Whatever the encoder throws.
    func encode(to encoder: Encoder) throws {
        try extras.encode(into: encoder)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)

        guard let payload = kind.encodablePayload else {
            try encodeUnknown(into: encoder, container: &container)
            return
        }
        try container.encode(kind.typeName, forKey: .type)
        try common.encode(to: encoder)
        try payload.encode(to: encoder)
    }

    /// Encodes a node of a type this build does not model, key by key as it was read.
    private func encodeUnknown(
        into encoder: Encoder,
        container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        guard case let .unknown(typeName, properties) = kind else { return }
        try container.encode(typeName, forKey: .type)
        try common.encode(to: encoder)
        var dynContainer = encoder.container(keyedBy: DynamicCodingKey.self)
        for (key, value) in properties {
            try dynContainer.encode(value, forKey: DynamicCodingKey(stringValue: key))
        }
    }
}

// MARK: - Refusing an unknown type

extension PenNode {
    /// The refusal an authored node of an unmodelled type earns.
    ///
    /// Names the type as written and every real one, because a caller who wrote
    /// `video_clip` needs the list more than a restatement of the guess.
    ///
    /// - Parameters:
    ///   - typeName: The `type` the input wrote.
    ///   - path: Where in the input the `type` key is.
    /// - Returns: The error to throw.
    static func unknownTypeRefusal(_ typeName: String, at path: [CodingKey]) -> DecodingError {
        let types = NodeType.allCases.map(\.rawValue).joined(separator: ", ")
        return DecodingError.dataCorrupted(DecodingError.Context(
            codingPath: path,
            debugDescription: "\"\(typeName)\" is not a node type; the types are \(types)"
        ))
    }
}

// MARK: - Kind + Codable

public extension PenNode.Kind {
    // Codable is handled by PenNode's init(from:)/encode(to:) above.
    // The compiler needs explicit conformance since the unknown case has associated values
    // that include [String: AnyCodable], which is Codable but the compiler can't auto-synthesize
    // for an enum with heterogeneous associated values.

    init(from decoder: Decoder) throws {
        // This should never be called directly — PenNode's init handles dispatch.
        throw DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "PenNode.Kind should not be decoded directly; use PenNode's init(from:)"
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        // This should never be called directly — PenNode's encode handles dispatch.
        throw EncodingError.invalidValue(
            self,
            EncodingError.Context(
                codingPath: encoder.codingPath,
                debugDescription: "PenNode.Kind should not be encoded directly; use PenNode's encode(to:)"
            )
        )
    }
}
