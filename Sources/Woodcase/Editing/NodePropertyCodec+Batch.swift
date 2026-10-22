//
//  NodePropertyCodec+Batch.swift
//  Woodcase
//

import Foundation

/// Writing a node's many properties at once, each payload overlaid once.
///
/// ``setting(_:at:on:)`` costs one pass over the payload it writes — its keys captured,
/// the payload decoded again over the new value (``patchingPayload(_:field:value:)``) — so
/// a patch of N keys used to cost N passes. A proportional scale writes up to a dozen keys
/// of a node — a stack's size, gap, padding, radii and stroke — and a gesture's preview
/// patches them all again at every step.
/// ``setting(_:on:)`` lays every plain `common.*` key over the `common` payload in one pass
/// and every plain `kind.*` key over the `kind` payload in another.
///
/// It is held to the per-key writes it replaces, key for key: the same node, the same
/// refusal naming the same key. A key that is not a plain payload key — an `extras.*` key,
/// a natural path (`note.fontSize`, `codegen.role`), a `kind.effects` naming a spread, any
/// key of an instance or of an unrecognized type, any key that would be refused — is
/// written on its own, in its turn, with the plain keys before it written first, so two
/// keys that store into the same place land in the order the per-key writes would have
/// put them — ``applicationOrder(of:)``, the same in every process. Where the one pass
/// declines or refuses, the keys it held are written again one at a time from where they
/// started, which gives exactly the per-key outcome.
extension NodePropertyCodec {
    /// Returns a copy of `node` with every property in `properties` set.
    ///
    /// Equal to writing each entry with ``setting(_:at:on:)`` in
    /// ``applicationOrder(of:)`` — broadest storage first, ties by path — so every process
    /// and every replica writes a map the same way however its dictionary iterates, and
    /// costing at most one payload pass for all of its plain `common.*` keys and one for
    /// all of its plain `kind.*` keys. A map of one key is written as it stands, unsorted.
    ///
    /// - Parameters:
    ///   - properties: The values to write, keyed by property path — any path
    ///     ``setting(_:at:on:)`` takes.
    ///   - node: The node to patch.
    /// - Returns: The patched node.
    /// - Throws: Whatever the first refused key's ``setting(_:at:on:)`` throws:
    ///   ``EditingError/unknownProperty(nodeID:key:nodeType:)`` or
    ///   ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)``.
    public static func setting(_ properties: [String: AnyCodable], on node: PenNode) throws -> PenNode {
        guard properties.count > 1 else { return try setting(inOrder: properties, on: node) }
        return try setting(inOrder: applicationOrder(of: properties), on: node)
    }

    /// Writes `entries` in the order given, batching the plain payload keys.
    ///
    /// - Parameters:
    ///   - entries: The writes, already in ``applicationOrder(of:)``.
    ///   - node: The node to patch.
    /// - Returns: The patched node.
    /// - Throws: Whatever the first refused key's ``setting(_:at:on:)`` throws.
    private static func setting(
        inOrder entries: some Sequence<(key: String, value: AnyCodable)>, on node: PenNode
    ) throws -> PenNode {
        var batch = Batch(node: node)
        for (path, value) in entries {
            guard let write = payloadWrite(value, at: path, on: node) else {
                try batch.flush()
                batch.node = try setting(value, at: path, on: batch.node)
                continue
            }
            if !batch.accepts(write) {
                try batch.flush()
            }
            batch.pending.append(write)
        }
        try batch.flush()
        return batch.node
    }

    /// The write of a plain payload key, or `nil` for a key ``setting(_:at:on:)`` treats
    /// any other way — or would refuse.
    ///
    /// - Parameters:
    ///   - value: The value written.
    ///   - path: The path it is written to.
    ///   - node: The node it is written to. Only its id and its kind's case are read, and
    ///     no write changes either, so the node as the batch began will do.
    /// - Returns: The write, its value coerced as ``setting(_:at:on:)`` coerces it.
    private static func payloadWrite(_ value: AnyCodable, at path: String, on node: PenNode) -> PayloadWrite? {
        guard !isExtrasPath(path), naturalKey(of: path, on: node.kind) == nil, naturalStoragePath(of: path) == nil,
              !writesNamedSpread([path: value], on: node.kind)
        else { return nil }
        let written = coercing(value, at: path, on: node.kind)
        if path.hasPrefix(commonPrefix) {
            guard commonPaths.contains(path) else { return nil }
            let field = String(path.dropFirst(commonPrefix.count))
            return PayloadWrite(path: path, value: value, payload: .common, key: jsonKey(for: field), written: written)
        }
        guard path.hasPrefix(kindPrefix), payloadKinds(node.kind),
              let field = try? kindField(of: path, in: node.kind, nodeID: node.id)
        else { return nil }
        return PayloadWrite(path: path, value: value, payload: .kind, key: jsonKey(for: field), written: written)
    }

    /// Whether a kind's keys are written through its payload's `Codable` conformance — every
    /// kind but an instance's and an unrecognized type's, which ``setting(_:at:on:kind:nodeID:)``
    /// writes field by field.
    private static func payloadKinds(_ kind: PenNode.Kind) -> Bool {
        switch kind {
        case .ref, .unknown: false
        default: true
        }
    }

    /// Returns `kind` with every key of `patch` laid over its payload in one pass, or `nil`
    /// where the overlay declines.
    ///
    /// - Parameters:
    ///   - kind: A kind ``payloadKinds(_:)`` accepts.
    ///   - patch: The keys to write, as the payload's `CodingKeys` spell them;
    ///     ``AnyCodable/null`` removes one.
    /// - Returns: A kind of the same case carrying the patched payload.
    /// - Throws: The `DecodingError` the payload raises for a new value.
    private static func overlayingKind(_ kind: PenNode.Kind, patch: [String: AnyCodable]) throws -> PenNode.Kind? {
        switch kind {
        case let .frame(data): try overlaying(data, patch: patch).map(PenNode.Kind.frame)
        case let .text(data): try overlaying(data, patch: patch).map(PenNode.Kind.text)
        case let .rectangle(data): try overlaying(data, patch: patch).map(PenNode.Kind.rectangle)
        case let .ellipse(data): try overlaying(data, patch: patch).map(PenNode.Kind.ellipse)
        case let .path(data): try overlaying(data, patch: patch).map(PenNode.Kind.path)
        case let .group(data): try overlaying(data, patch: patch).map(PenNode.Kind.group)
        case let .line(data): try overlaying(data, patch: patch).map(PenNode.Kind.line)
        case let .polygon(data): try overlaying(data, patch: patch).map(PenNode.Kind.polygon)
        case let .note(data): try overlaying(data, patch: patch).map(PenNode.Kind.note)
        case let .prompt(data): try overlaying(data, patch: patch).map(PenNode.Kind.prompt)
        case let .context(data): try overlaying(data, patch: patch).map(PenNode.Kind.context)
        case let .icon(data): try overlaying(data, patch: patch).map(PenNode.Kind.icon)
        case let .script(data): try overlaying(data, patch: patch).map(PenNode.Kind.script)
        case let .browser(data): try overlaying(data, patch: patch).map(PenNode.Kind.browser)
        case let .connection(data): try overlaying(data, patch: patch).map(PenNode.Kind.connection)
        case .ref, .unknown: nil
        }
    }
}

extension NodePropertyCodec {
    /// One plain payload key's write, held until its batch is flushed.
    private struct PayloadWrite {
        /// Which of a node's two payloads a key belongs to.
        enum Payload {
            case common, kind
        }

        /// The path as the caller wrote it.
        let path: String
        /// The value as the caller wrote it, for a per-key replay.
        let value: AnyCodable
        /// The payload the key belongs to.
        let payload: Payload
        /// The JSON key, as the payload's `CodingKeys` spell it.
        let key: String
        /// The value to store, after ``coercing(_:at:on:)``.
        let written: AnyCodable
    }

    /// The node so far, and the plain writes not yet laid over it.
    private struct Batch {
        /// The node with every write before ``pending`` applied.
        var node: PenNode
        /// Plain writes, in the order they were met; no two share a payload and a key.
        var pending: [PayloadWrite] = []

        /// Whether `write` can join ``pending``: no pending write names the same key of the
        /// same payload, which only another spelling of one field could.
        func accepts(_ write: PayloadWrite) -> Bool {
            !pending.contains { $0.payload == write.payload && $0.key == write.key }
        }

        /// Lays ``pending`` over ``node`` — each payload in one pass — and empties it.
        ///
        /// Where a pass declines or a value is refused, the pending writes are replayed one
        /// at a time from ``node``, so the outcome, and the refusal, are the per-key ones.
        mutating func flush() throws {
            guard !pending.isEmpty else { return }
            let writes = pending
            pending = []
            if let patched = try? Self.overlaying(writes, on: node) {
                node = patched
                return
            }
            for write in writes {
                node = try NodePropertyCodec.setting(write.value, at: write.path, on: node)
            }
        }

        /// `node` with `writes` laid over it, or `nil` where an overlay declines.
        private static func overlaying(_ writes: [PayloadWrite], on node: PenNode) throws -> PenNode? {
            var common: [String: AnyCodable] = [:]
            var kind: [String: AnyCodable] = [:]
            for write in writes {
                switch write.payload {
                case .common: common[write.key] = write.written
                case .kind: kind[write.key] = write.written
                }
            }
            var patched = node
            if !common.isEmpty {
                guard let overlaid = try NodePropertyCodec.overlaying(node.common, patch: common) else { return nil }
                patched.common = overlaid
            }
            if !kind.isEmpty {
                guard let overlaid = try NodePropertyCodec.overlayingKind(node.kind, patch: kind) else { return nil }
                patched.kind = overlaid
            }
            return patched
        }
    }
}
