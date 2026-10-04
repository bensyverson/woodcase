//
//  PenPostIt+Metadata.swift
//  Woodcase
//

import Foundation

public extension PenPostIt {
    /// A post-it's metadata, read as typed values.
    ///
    /// Reading is lenient, because a file is: a value the convention does not spell
    /// reads as ``Field/unrecognized(_:)`` holding what the file wrote, rather than
    /// refusing the file or losing the value. Writing is strict — an agent's write is
    /// held to the convention by ``NodePropertyCodec/checkAuthored(_:on:)``.
    ///
    /// ```swift
    /// if let postIt = PenPostIt.Metadata(node), postIt.state == .valid(.open) {
    ///     print(postIt.author ?? "anonymous")
    /// }
    /// ```
    struct Metadata: Friendly {
        /// A typed key's value: one the convention spells, or what the file wrote instead.
        public enum Field<Value: Friendly>: Friendly {
            /// A value the convention spells.
            case valid(Value)
            /// A value it does not, as the file wrote it (a non-string as its JSON).
            case unrecognized(String)

            /// The typed value, or `nil` when it was not recognized.
            public var value: Value? {
                if case let .valid(value) = self { return value }
                return nil
            }
        }

        /// Reads a node's metadata as a post-it's.
        ///
        /// - Parameter node: Any node.
        /// - Returns: The post-it metadata, or `nil` unless `metadata.type` is
        ///   ``PenPostIt/typeValue``.
        public init?(_ node: PenNode) {
            guard let metadata = node.common.metadata else { return nil }
            self.init(metadata)
        }

        /// Reads a metadata object as a post-it's.
        ///
        /// - Parameter metadata: A node's metadata.
        /// - Returns: The post-it metadata, or `nil` unless its `type` is
        ///   ``PenPostIt/typeValue``.
        public init?(_ metadata: PenMetadata) {
            guard metadata.type == PenPostIt.typeValue else { return nil }
            let read = { (key: Key) in metadata[key.rawValue] }
            kind = read(.kind).map { Self.field($0, Kind.init(rawValue:)) }
            state = read(.state).map { Self.field($0, State.init(rawValue:)) }
            tint = read(.tint).map { Self.field($0, PenPostIt.tint) }
            author = read(.author).flatMap(Self.string)
            leaf = read(.leaf).flatMap(Self.string)
            stage = read(.stage).flatMap(Self.string)
            copiedFrom = read(.copiedFrom).flatMap(Self.string)
        }

        /// What the post-it is for.
        public var kind: Field<Kind>?
        /// Whether it still asks for attention.
        public var state: Field<State>?
        /// Who wrote it.
        public var author: String?
        /// The task it belongs to.
        public var leaf: String?
        /// The part of the work it sits in.
        public var stage: String?
        /// Its paper color; `nil` means Post-it yellow.
        public var tint: Field<PenHexColor>?
        /// On a copy, the original author, until the copier first edits it.
        public var copiedFrom: String?

        // MARK: - Reading

        /// A typed field: the parsed value, or what the file wrote when it does not parse.
        private static func field<Value>(
            _ value: AnyCodable,
            _ parse: (String) -> Value?
        ) -> Field<Value> {
            if let text = string(value), let parsed = parse(text) { return .valid(parsed) }
            return .unrecognized(string(value) ?? PenPostIt.json(value))
        }

        /// A string value, or `nil` for any other JSON.
        private static func string(_ value: AnyCodable) -> String? {
            if case let .string(text) = value { return text }
            return nil
        }
    }
}
