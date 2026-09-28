//
//  BatchOperation+Codable.swift
//  Woodcase
//

import Foundation

public extension BatchOperation {
    /// The field names of the batch grammar, shared by every verb that uses them.
    private enum CodingKeys: String, CodingKey {
        case op, target, parent, source, node, props, each, at, tag, detach, rev, name, value, options
        case unset, alias, path
        case guards = "guard"
    }

    /// The `"parent"` field, where ``NodeAddress/documentRoot`` means the document root.
    ///
    /// The same synonym `<parent|document>` is on argv, decided in one place so a batch
    /// and a verb cannot disagree about the word. A root node genuinely named `document`
    /// is still addressable as `#<id>`, which is the trade a literal always asks for.
    ///
    /// - Parameter container: The line's decoding container.
    /// - Returns: The parent address, or `nil` for the document root and for a line that
    ///   named no parent at all.
    /// - Throws: `DecodingError.dataCorrupted` when the value is not an address.
    private static func parent(
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> NodeAddress? {
        guard let raw = try container.decodeIfPresent(String.self, forKey: .parent) else { return nil }
        guard raw != NodeAddress.documentRoot else { return nil }
        guard let address = NodeAddress(raw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .parent, in: container,
                debugDescription: "'\(raw)' is not a node address"
            )
        }
        return address
    }

    /// The `"guard"` field, written as one pin or as an array of them.
    ///
    /// One pin is the common case and reads as one value; a line that asserts several
    /// premises writes a list rather than repeating the key, which JSON cannot do.
    ///
    /// - Parameter container: The line's decoding container.
    /// - Returns: The pins, in written order, empty when the field is absent.
    /// - Throws: Whatever ``BatchGuard`` throws for a value that is neither shape.
    private static func guards(
        in container: KeyedDecodingContainer<CodingKeys>
    ) throws -> [BatchGuard] {
        if let many = try? container.decodeIfPresent([BatchGuard].self, forKey: .guards) {
            return many
        }
        return try container.decodeIfPresent(BatchGuard.self, forKey: .guards).map { [$0] } ?? []
    }

    /// Writes the `"guard"` field in the shape it was read in, and not at all when the
    /// line is unguarded.
    private static func encode(
        _ guards: [BatchGuard],
        into container: inout KeyedEncodingContainer<CodingKeys>
    ) throws {
        switch guards.count {
        case 0: break
        case 1: try container.encode(guards[0], forKey: .guards)
        default: try container.encode(guards, forKey: .guards)
        }
    }

    /// Decodes one batch line, dispatching on its `"op"` field.
    ///
    /// A node written under `node` may omit its ids; see ``PenSubtreeDecoder``.
    ///
    /// - Parameter decoder: The decoder to read from.
    /// - Throws: `DecodingError.dataCorrupted` when `"op"` names no known verb,
    ///   and whatever the operation's own fields throw.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try container.decode(String.self, forKey: .op)
        guard let verb = Verb(rawValue: raw) else {
            let known = Verb.allCases.map(\.rawValue).joined(separator: ", ")
            throw DecodingError.dataCorruptedError(
                forKey: .op, in: container,
                debugDescription: "'\(raw)' is not a batch operation; expected one of: \(known)"
            )
        }

        let guards = try Self.guards(in: container)
        switch verb {
        case .set:
            self = try .set(SetOp(
                target: container.decode(NodeAddress.self, forKey: .target),
                props: container.decode([String: AnyCodable].self, forKey: .props),
                rev: container.decodeIfPresent(String.self, forKey: .rev),
                guards: guards
            ))
        case .add:
            self = try .add(AddOp(
                node: PenSubtreeDecoder.node(from: container.decode(AnyCodable.self, forKey: .node)),
                parent: Self.parent(in: container),
                at: container.decodeIfPresent(Int.self, forKey: .at),
                tag: container.decodeIfPresent(String.self, forKey: .tag),
                rev: container.decodeIfPresent(String.self, forKey: .rev),
                guards: guards
            ))
        case .replace:
            self = try .replace(ReplaceOp(
                target: container.decode(NodeAddress.self, forKey: .target),
                node: PenSubtreeDecoder.node(from: container.decode(AnyCodable.self, forKey: .node)),
                rev: container.decodeIfPresent(String.self, forKey: .rev),
                guards: guards
            ))
        case .cp:
            self = try .cp(CopyOp(
                source: container.decode(NodeAddress.self, forKey: .source),
                parent: Self.parent(in: container),
                at: container.decodeIfPresent(Int.self, forKey: .at),
                tag: container.decodeIfPresent(String.self, forKey: .tag),
                props: container.decodeIfPresent([String: AnyCodable].self, forKey: .props),
                each: container.decodeIfPresent([[String: AnyCodable]].self, forKey: .each),
                rev: container.decodeIfPresent(String.self, forKey: .rev),
                guards: guards
            ))
        case .mv:
            self = try .mv(MoveOp(
                target: container.decode(NodeAddress.self, forKey: .target),
                parent: Self.parent(in: container),
                at: container.decodeIfPresent(Int.self, forKey: .at),
                rev: container.decodeIfPresent(String.self, forKey: .rev),
                guards: guards
            ))
        case .rm:
            self = try .rm(RemoveOp(
                target: container.decode(NodeAddress.self, forKey: .target),
                detach: container.decodeIfPresent(Bool.self, forKey: .detach) ?? false,
                rev: container.decodeIfPresent(String.self, forKey: .rev),
                guards: guards
            ))
        case .override:
            // A line may write, remove, or do both, so neither field is required on
            // its own; a line with neither is refused when it is planned.
            self = try .override(OverrideOp(
                target: container.decode(NodeAddress.self, forKey: .target),
                props: container.decodeIfPresent([String: AnyCodable].self, forKey: .props) ?? [:],
                unset: container.decodeIfPresent([String].self, forKey: .unset) ?? [],
                rev: container.decodeIfPresent(String.self, forKey: .rev),
                guards: guards
            ))
        case .variable:
            self = try .variable(VariableOp(
                name: container.decode(String.self, forKey: .name),
                value: container.decode(PenVariable.self, forKey: .value),
                guards: guards
            ))
        case .themeAxis:
            self = try .themeAxis(ThemeAxisOp(
                name: container.decode(String.self, forKey: .name),
                options: container.decode([String].self, forKey: .options),
                guards: guards
            ))
        case .importOp:
            self = try .importOp(ImportOp(
                alias: container.decode(String.self, forKey: .alias),
                path: container.decode(String.self, forKey: .path),
                guards: guards
            ))
        }
    }

    /// Encodes one batch line as a flat JSON object headed by its `"op"` field.
    ///
    /// Fields the operation left unset are omitted, so a re-encoded line is as
    /// terse as a hand-written one.
    ///
    /// - Parameter encoder: The encoder to write to.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(verb.rawValue, forKey: .op)
        try Self.encode(guards, into: &container)

        switch self {
        case let .set(op):
            try container.encode(op.target, forKey: .target)
            try container.encode(op.props, forKey: .props)
            try container.encodeIfPresent(op.rev, forKey: .rev)
        case let .add(op):
            try container.encodeIfPresent(op.parent, forKey: .parent)
            try container.encode(op.node, forKey: .node)
            try container.encodeIfPresent(op.at, forKey: .at)
            try container.encodeIfPresent(op.tag, forKey: .tag)
            try container.encodeIfPresent(op.rev, forKey: .rev)
        case let .replace(op):
            try container.encode(op.target, forKey: .target)
            try container.encode(op.node, forKey: .node)
            try container.encodeIfPresent(op.rev, forKey: .rev)
        case let .cp(op):
            try container.encode(op.source, forKey: .source)
            try container.encodeIfPresent(op.parent, forKey: .parent)
            try container.encodeIfPresent(op.at, forKey: .at)
            try container.encodeIfPresent(op.tag, forKey: .tag)
            try container.encodeIfPresent(op.props, forKey: .props)
            try container.encodeIfPresent(op.each, forKey: .each)
            try container.encodeIfPresent(op.rev, forKey: .rev)
        case let .mv(op):
            try container.encode(op.target, forKey: .target)
            try container.encodeIfPresent(op.parent, forKey: .parent)
            try container.encodeIfPresent(op.at, forKey: .at)
            try container.encodeIfPresent(op.rev, forKey: .rev)
        case let .rm(op):
            try container.encode(op.target, forKey: .target)
            if op.detach { try container.encode(true, forKey: .detach) }
            try container.encodeIfPresent(op.rev, forKey: .rev)
        case let .override(op):
            try container.encode(op.target, forKey: .target)
            if !op.props.isEmpty { try container.encode(op.props, forKey: .props) }
            if !op.unset.isEmpty { try container.encode(op.unset, forKey: .unset) }
            try container.encodeIfPresent(op.rev, forKey: .rev)
        case let .variable(op):
            try container.encode(op.name, forKey: .name)
            try container.encode(op.value, forKey: .value)
        case let .themeAxis(op):
            try container.encode(op.name, forKey: .name)
            try container.encode(op.options, forKey: .options)
        case let .importOp(op):
            try container.encode(op.alias, forKey: .alias)
            try container.encode(op.path, forKey: .path)
        }
    }
}
