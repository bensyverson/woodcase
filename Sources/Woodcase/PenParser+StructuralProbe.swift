//
//  PenParser+StructuralProbe.swift
//  Woodcase
//

import Foundation

extension PenParser {
    /// Decides whether a document declaring another major version is still a document
    /// this build can read, and decodes it if so.
    ///
    /// A different major is not refused on its number alone: a 3.0 that kept 2.x's
    /// shape reads perfectly well, and refusing it would strand the reader for no
    /// reason. It is read — read-only, with a warning — when all of these hold:
    ///
    /// - the root is an object with a `children` array;
    /// - every node, at every depth, is an object with a string `id` and `type`;
    /// - at least one node is of a type this build models;
    /// - the whole document decodes with the modeled decoder, which is where a key
    ///   this build models but that now holds a differently shaped value is caught.
    ///
    /// An unknown node type is not a conflict — the decoder keeps it as
    /// ``PenNode/Kind/unknown(typeName:properties:)``. Anything else fails with
    /// ``PenParserError/differentMajor(url:version:reason:)`` naming the first thing
    /// that did not read.
    enum StructuralProbe {
        /// Decodes `data` if it passes the probe.
        ///
        /// - Parameters:
        ///   - data: The document's bytes.
        ///   - version: The version the document declares, for the error.
        /// - Returns: The decoded document, still declaring `version`.
        /// - Throws: ``PenParserError/decodingFailed(url:underlying:)`` for bytes that
        ///   are not JSON; ``PenParserError/differentMajor(url:version:reason:)`` for a
        ///   document that fails the probe.
        static func decode(_ data: Data, declaring version: String) throws -> PenDocument {
            let root: AnyCodable
            do {
                root = try JSONDecoder().decode(AnyCodable.self, from: data)
            } catch {
                throw PenParserError.decodingFailed(url: nil, underlying: error)
            }
            let refuse = { (reason: String) in
                PenParserError.differentMajor(url: nil, version: version, reason: reason)
            }

            guard case let .dictionary(object) = root, case let .array(children)? = object["children"] else {
                throw refuse("it has no \"children\" array")
            }
            var modeled = 0
            if let failure = firstFailure(in: children, at: "children", modeled: &modeled) {
                throw refuse(failure)
            }
            guard modeled > 0 else {
                throw refuse("it holds no node of a type this build models")
            }
            do {
                return try JSONDecoder().decode(PenDocument.self, from: data)
            } catch {
                throw refuse(DecodingReason.describe(error))
            }
        }

        /// The first node in `nodes`, at any depth, that is not an object with a string
        /// `id` and `type`, described with its path; `nil` when every node has both.
        ///
        /// - Parameters:
        ///   - nodes: A `children` array.
        ///   - path: The array's path, for the description.
        ///   - modeled: Incremented once for each node whose type this build models.
        private static func firstFailure(
            in nodes: [AnyCodable],
            at path: String,
            modeled: inout Int
        ) -> String? {
            for (index, node) in nodes.enumerated() {
                let nodePath = "\(path)[\(index)]"
                guard case let .dictionary(fields) = node else {
                    return "\(nodePath) is not an object"
                }
                guard case .string? = fields["id"] else {
                    return "\(nodePath) has no string \"id\""
                }
                guard case let .string(type)? = fields["type"] else {
                    return "\(nodePath) has no string \"type\""
                }
                if PenNode.NodeType(rawValue: type) != nil {
                    modeled += 1
                }
                if case let .array(children)? = fields["children"],
                   let failure = firstFailure(in: children, at: "\(nodePath).children", modeled: &modeled)
                {
                    return failure
                }
            }
            return nil
        }
    }
}
