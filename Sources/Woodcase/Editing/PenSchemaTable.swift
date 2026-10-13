//
//  PenSchemaTable.swift
//  Woodcase
//

import Foundation

/// One table of the property vocabulary: the `common.*` properties, or one node type's.
///
/// A row is everything a caller needs before writing a value — the codec path `set`
/// takes, the key the .pen file writes it under, the union of forms it accepts with
/// every spelling in full, the type a `$variable` there must have, and the key tables of
/// anything nested. None of it is written out here: ``PenSchema`` assembles it from the
/// decoders' own vocabulary.
public struct PenSchemaTable: Friendly {
    /// Creates a table.
    ///
    /// - Parameters:
    ///   - type: The node type it describes, or `nil` for the shared properties.
    ///   - summary: One phrase saying what the table covers.
    ///   - properties: The rows, sorted by path.
    public init(type: PenNode.NodeType?, summary: String, properties: [Property]) {
        self.type = type
        self.summary = summary
        self.properties = properties
    }

    /// The node type this table describes, or `nil` for the `common.*` table.
    public let type: PenNode.NodeType?

    /// One phrase saying what the table covers.
    public let summary: String

    /// The rows, sorted by path.
    public let properties: [Property]

    /// Every nested key table any row references, at any depth, each named once.
    public var nested: [PenNestedShape] {
        var seen = Set<String>()
        return properties.flatMap(\.nested).filter { seen.insert($0.name).inserted }
    }

    // MARK: - Property

    /// One row: a property, and everything a caller has to know to write it.
    public struct Property: Friendly {
        /// Creates a row.
        ///
        /// - Parameters:
        ///   - path: The codec path `set` and `cp` accept.
        ///   - key: Where the .pen file writes the value.
        ///   - shape: The wire shape the decoders accept.
        ///   - default: What the engine uses when a node leaves the property unset, or
        ///     `nil` when it uses nothing.
        public init(path: String, key: PenKeyForm, shape: PenPropertyShape, default: PenPropertyDefault? = nil) {
            self.path = path
            self.key = key
            self.shape = shape
            self.default = `default`
        }

        /// The codec path `set` and `cp` accept — `kind.fills`.
        public let path: String

        /// Where the .pen file writes the value — under `fill`, or inlined.
        public let key: PenKeyForm

        /// The wire shape the decoders accept.
        public let shape: PenPropertyShape

        /// What the layout engine and renderer use when a node leaves the property unset
        /// — `"horizontal"` for a frame's `layout`, 16 for a text's `fontSize`, 13 for a
        /// note's — or `nil` when an unset property draws nothing in its place (`fills`)
        /// or the engine never reads it (`name`).
        ///
        /// It depends on the node type as well as the property, so a row from
        /// ``PenSchema/table(for:)`` carries its type's default; the `common.*` rows'
        /// defaults are the same on every type.
        public let `default`: PenPropertyDefault?

        /// The accepted forms as one union — `color | fill | [color | fill, …]`.
        public var value: String {
            shape.signature
        }

        /// Every exact spelling this property accepts, empty when no enumeration decides it.
        public var spellings: [String] {
            shape.spellings
        }

        /// The type a `$variable` written here must have, or `nil` if none is accepted.
        public var variable: PenVariableType? {
            shape.variable
        }

        /// The nested key tables this property references, at any depth.
        public var nested: [PenNestedShape] {
            shape.nested
        }

        /// A literal this property accepts, ready to paste after an `=`.
        public var example: String? {
            shape.example
        }

        /// The range, step and unit a number written here must keep to, or `nil`.
        public var constraint: PenValueConstraint? {
            shape.constraint
        }
    }
}
