//
//  NodePropertyCodec+OverrideAuthoring.swift
//  Woodcase
//

import Foundation

/// The authoring check on the overrides an agent writes.
///
/// An override is stored raw and only decoded when the instance expands, and that
/// decode reads a *file* — it keeps a key it does not know and a node `type` it does not
/// model. So an agent's override is held here to what ``checkAuthored(_:on:)`` holds a
/// `set` to, before the edit exists: `override`, and a `cp` of a component whose
/// path-keyed properties become overrides, both come through the batch planner's one
/// override path, which calls this.
public extension NodePropertyCodec {
    /// Refuses an authored override that carries a key, a fill or effect `type`, or a
    /// node `type` the model does not claim.
    ///
    /// Three things are checked. An override that names a `type` replaces the node
    /// whole, so it is decoded whole, as an authored node. Otherwise `children` — how an
    /// instance fills a slot — is decoded as authored nodes, and `fill`, `stroke` and
    /// `effect` as authored paint and effects. A value equal to what the node already
    /// holds is let through, so writing back what a read returned stays possible even
    /// when the file gave it extras.
    ///
    /// - Parameters:
    ///   - properties: The override's values, keyed by raw .pen key.
    ///   - definition: The node inside the component the override patches, as this
    ///     instance already shows it, or `nil` when the document cannot tell.
    ///   - refID: The instance's `ref` node id.
    ///   - descendantKey: The `descendants` key, or `nil` for a root override.
    /// - Throws: ``EditingError/overrideValueRejected(refID:descendantKey:key:expected:actual:)``,
    ///   or ``EditingError/rootOverrideValueRejected(refID:key:expected:actual:)`` for a
    ///   root override, naming the first refused key.
    static func checkAuthoredOverride(
        _ properties: [String: AnyCodable],
        on definition: PenNode?,
        refID: String,
        descendantKey: String?
    ) throws {
        func refusal(_ key: String, expected: String, actual: String) -> EditingError {
            guard let descendantKey else {
                return .rootOverrideValueRejected(refID: refID, key: key, expected: expected, actual: actual)
            }
            return .overrideValueRejected(
                refID: refID, descendantKey: descendantKey, key: key, expected: expected, actual: actual
            )
        }

        if properties[PenDescendantOverride.typeKey] != nil {
            do {
                _ = try PenSubtreeDecoder.node(from: .dictionary(properties))
            } catch {
                throw refusal(
                    PenDescendantOverride.typeKey,
                    expected: "a whole node of a type the format has, with only the keys that type claims",
                    actual: describe(.dictionary(properties), failure: error)
                )
            }
            return
        }

        let current = definition.flatMap { try? encode($0) }
        for key in properties.keys.sorted() {
            let value = properties[key] ?? .null
            if case .null = value { continue }
            if case let .dictionary(stored)? = current, stored[key] == value { continue }
            do {
                if key == PenNodePatcher.childrenKey {
                    try decodeAuthoredChildren(value)
                } else if let shape = AuthoredShape(field: fieldName(forRawKey: key)) {
                    try shape.decode(value)
                }
            } catch {
                let field = fieldName(forRawKey: key)
                throw refusal(
                    key,
                    expected: key == PenNodePatcher.childrenKey
                        ? "an array of nodes, each of a type the format has"
                        : expectedShape(of: field),
                    actual: describe(value, failure: error)
                )
            }
        }
    }
}

// MARK: - Private

private extension NodePropertyCodec {
    /// Decodes a slot's `children` as authored nodes, ids optional.
    static func decodeAuthoredChildren(_ value: AnyCodable) throws {
        guard case let .array(children) = value else {
            throw DecodingError.typeMismatch([AnyCodable].self, DecodingError.Context(
                codingPath: [], debugDescription: "children is an array of nodes"
            ))
        }
        let data = try JSONEncoder().encode(AnyCodable.array(children.map(PenSubtreeDecoder.withPlaceholderIDs)))
        let decoder = JSONDecoder()
        decoder.userInfo[PenDecodingMode.userInfoKey] = PenDecodingMode.authoring
        _ = try decoder.decode([PenNode].self, from: data)
    }

    /// A refused value's JSON type, with the clause locating what inside it was refused.
    static func describe(_ value: AnyCodable, failure: Error) -> String {
        actualShape(of: value, field: "", failure: failure)
    }
}
