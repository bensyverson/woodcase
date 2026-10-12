//
//  EditPlanner+Position.swift
//  Woodcase
//

import Foundation

/// Refusing an `x` or `y` that layout would store and ignore.
///
/// A child of a frame that lays out its children (`layout` is `horizontal` or
/// `vertical`, and a frame that says nothing is horizontal) is placed by its parent
/// unless it is `layoutPosition: absolute`. An `x` written to it applies, reads back,
/// and moves nothing — so it is refused, with the write that would move it. The rule
/// is the layout engine's own (`PenLayoutEngine+FlexLayout.swift` splits flow from
/// absolute children the same way); a write that also makes the node absolute is
/// judged by the position it will have.
extension EditPlanner {
    /// The position-relevant half of a write.
    struct PositionWrite {
        /// Which vocabulary the write's keys are in.
        enum Vocabulary {
            /// `common.x`, `common.layoutPosition`: a set on a node's own storage.
            case propertyPath

            /// `x`, `layoutPosition`: an override.
            case rawKey

            /// The key `field` is written under in this vocabulary.
            func key(_ field: String) -> String {
                switch self {
                case .propertyPath: NodePropertyCodec.commonPrefix + field
                case .rawKey: field
                }
            }
        }

        /// The write's values, keyed in ``vocabulary``.
        var properties: [String: AnyCodable]

        /// Which vocabulary those keys are in.
        var vocabulary: Vocabulary
    }

    /// Refuses a changed `x` or `y` on a node its parent lays out.
    ///
    /// - Parameters:
    ///   - write: The write.
    ///   - placed: The node as it stands and its parent, or `nil` when they cannot be
    ///     found — a broken instance, say — in which case nothing is refused.
    ///   - address: The address as written.
    /// - Throws: ``EditRefusal`` with ``EditRefusal/Code/positionIgnoredByLayout``.
    static func checkPosition(
        _ write: PositionWrite,
        of placed: PlacedNode?,
        address: String
    ) throws {
        guard let placed, let parent = placed.parent, lays(outChildrenOf: parent) else { return }
        let positionKey = write.vocabulary.key(positionField)
        let position: PenLayoutPosition? = switch write.properties[positionKey] {
        case let .string(raw)?: PenLayoutPosition(rawValue: raw)
        case .null?: nil
        case nil: placed.node.common.layoutPosition
        default: placed.node.common.layoutPosition
        }
        guard position != .absolute else { return }

        for field in coordinateFields {
            let key = write.vocabulary.key(field)
            guard let value = write.properties[key], value != .null,
                  value != (try? NodePropertyCodec.value(at: NodePropertyCodec.commonPrefix + field, of: placed.node))
            else { continue }
            let parentName = placed.parentPath
            let suggestion = "\(positionKey)=\(PenLayoutPosition.absolute.rawValue)"
            throw EditRefusal(
                code: .positionIgnoredByLayout,
                address: address,
                property: key,
                expected: "no \(field) while \(parentName) lays it out",
                suggestion: suggestion,
                message: "\(address) sits in \(parentName)'s \(direction(of: parent)) layout, which places it "
                    + "and ignores \(key) — write `\(suggestion)` in the same edit to place it by x and y, "
                    + "or reorder it instead"
            )
        }
    }

    // MARK: - Private

    /// The fields layout ignores on a flow child.
    private static let coordinateFields = ["x", "y"]

    /// The field that takes a child out of its parent's flow.
    private static let positionField = "layoutPosition"

    /// Whether a node places its children itself.
    private static func lays(outChildrenOf parent: PenNode) -> Bool {
        guard case let .frame(data) = parent.kind else { return false }
        return (data.layout ?? .horizontal) != .none
    }

    /// The parent's layout direction, as a sentence names it.
    private static func direction(of parent: PenNode) -> String {
        guard case let .frame(data) = parent.kind else { return "" }
        return (data.layout ?? .horizontal).rawValue
    }
}
