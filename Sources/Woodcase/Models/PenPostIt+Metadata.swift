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
    /// Every key is read through ``PenMetadata/subscript(woodcase:)``, so the old bare
    /// spellings of a `type: postit` object read too, the namespace winning.
    ///
    /// ```swift
    /// if let postIt = PenPostIt.Metadata(node), postIt.type == .valid(.comment), postIt.state == .valid(.open) {
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
        /// A prompt's `state` reads as ``runState`` rather than ``state``: a prompt's
        /// state is where its run stands (``PenPostIt/RunState``).
        ///
        /// - Parameter node: Any node.
        /// - Returns: The post-it metadata — every `note` and `prompt` has it, metadata or
        ///   not — or, for another node, what ``init(_:)-(PenMetadata)`` reads.
        public init?(_ node: PenNode) {
            switch node.kind {
            case .note:
                self.init(reading: node.common.metadata ?? PenMetadata(type: nil), isPrompt: false)
            case .prompt:
                self.init(reading: node.common.metadata ?? PenMetadata(type: nil), isPrompt: true)
            default:
                guard let metadata = node.common.metadata else { return nil }
                self.init(metadata)
            }
        }

        /// Reads a metadata object as a post-it's.
        ///
        /// - Parameter metadata: A node's metadata.
        /// - Returns: The post-it metadata, or `nil` unless the object carries a
        ///   convention key in either spelling (an old-style `type: postit` included).
        public init?(_ metadata: PenMetadata) {
            guard PenPostIt.keys.contains(where: { metadata[woodcase: $0] != nil }) else { return nil }
            self.init(reading: metadata, isPrompt: false)
        }

        /// Reads every convention key, from either spelling; a prompt's state as a run state.
        private init(reading metadata: PenMetadata, isPrompt: Bool) {
            let read = { (key: PenMetadata.WoodcaseKey) in metadata[woodcase: key] }
            type = read(.type).map { Self.field($0, NoteType.init(rawValue:)) }
            if isPrompt {
                runState = read(.state).map { Self.field($0, RunState.init(rawValue:)) }
            } else {
                state = read(.state).map { Self.field($0, State.init(rawValue:)) }
            }
            tint = read(.tint).map { Self.field($0, PenPostIt.tint) }
            author = read(.author).flatMap(Self.string)
            leaf = read(.leaf).flatMap(Self.string)
            stage = read(.stage).flatMap(Self.string)
            copiedFrom = read(.copiedFrom).flatMap(Self.string)
            anchor = read(.anchor)
            replyTo = read(.replyTo).flatMap(Self.string)
            requestedBy = read(.requestedBy).flatMap(Self.string)
        }

        /// What the note is; `nil` is a post-it too.
        public var type: Field<NoteType>?
        /// On a comment, whether its thread still asks for attention; `nil` on a prompt,
        /// whose state is ``runState``. Read on a plain note too, as the file wrote it, but
        /// a note has no state and nothing draws it.
        public var state: Field<State>?
        /// On a prompt, where its run stands; `nil` on any other node.
        public var runState: Field<RunState>?
        /// On a prompt, who pressed Run.
        public var requestedBy: String?
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
        /// On a comment thread's first message, what the comment is about, as written.
        public var anchor: AnyCodable?
        /// On a comment reply, the id of the thread's first message.
        public var replyTo: String?

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
