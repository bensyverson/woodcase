//
//  NodePropertyCodec+Authoring.swift
//  Woodcase
//

import Foundation

/// The authoring check on property values an agent writes.
///
/// ``setting(_:at:on:)`` is the funnel every property write goes through — an agent's
/// `set`, but also an undo replaying an old value and a CRDT peer's write — so it decodes
/// in ``PenDecodingMode/file`` and keeps whatever ``PenExtras`` the value carries. An
/// agent's value is held to more: a key a fill, stroke paint or effect does not claim, or
/// a `type` this build does not model, is refused before the edit exists. The batch
/// planner calls this for `set` and for a copy's own properties.
public extension NodePropertyCodec {
    /// Refuses an authored value that carries a key or a `type` the model does not claim.
    ///
    /// Only the three properties that can carry extras are checked: `kind.fills`,
    /// `kind.stroke` and `kind.effects`. A value equal to what the node already holds is
    /// let through, so reading a property and writing it straight back stays a no-op even
    /// when the file gave it extras.
    ///
    /// - Parameters:
    ///   - properties: The values to write, keyed by property path.
    ///   - node: The node they will be written to.
    /// - Throws: ``EditingError/propertyTypeMismatch(nodeID:key:expected:actual:)`` naming
    ///   the first refused key.
    static func checkAuthored(_ properties: [String: AnyCodable], on node: PenNode) throws {
        if case .unknown = node.kind { return }
        for (path, value) in properties.sorted(by: { $0.key < $1.key }) {
            guard let field = try? kindField(of: path, in: node.kind, nodeID: node.id),
                  let shape = AuthoredShape(field: field)
            else { continue }
            if case .null = value { continue }
            if let current = try? self.value(at: path, of: node), current == value { continue }
            do {
                try shape.decode(value)
            } catch {
                throw mismatch(path, field, value, node.id, error)
            }
        }
    }
}

// MARK: - Shapes

extension NodePropertyCodec {
    /// A property whose value is a payload that can carry ``PenExtras``.
    enum AuthoredShape: String, CaseIterable {
        case fills
        case stroke
        case effects

        /// The shape a field holds, or `nil` for a field whose value carries no extras.
        init?(field: String) {
            self.init(rawValue: field)
        }

        /// Decodes `value` as this shape in ``PenDecodingMode/authoring``.
        ///
        /// - Parameter value: The authored value.
        /// - Throws: The `DecodingError` an unclaimed key or unknown `type` raises.
        func decode(_ value: AnyCodable) throws {
            let decoder = JSONDecoder()
            decoder.userInfo[PenDecodingMode.userInfoKey] = PenDecodingMode.authoring
            let data = try JSONEncoder().encode(value)
            switch self {
            case .fills, .stroke: _ = try decoder.decode(PenFills.self, from: data)
            case .effects: _ = try decoder.decode(PenEffects.self, from: data)
            }
        }
    }
}
