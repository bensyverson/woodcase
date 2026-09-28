//
//  ScriptError.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import Woodcase

    /// Why a script run ended early, with everything needed to point at the line.
    ///
    /// A refusal from the editing layer keeps the sentence the verb would have printed —
    /// the remedy dialect, the candidate list on an ambiguous address, the near misses on
    /// a missing one — so the host trades none of the CLI's teaching for a stack trace.
    /// A throw from the script's own code keeps its message and gains the location
    /// JavaScriptCore recorded.
    ///
    /// ``source``, ``line`` and ``column`` describe *which* source: each is evaluated
    /// with its own source URL, so an error in the second `-F` file reports that file's
    /// line rather than a line in a concatenation.
    public struct ScriptError: Friendly {
        /// Records a failure.
        ///
        /// - Parameters:
        ///   - message: The sentence to show. A refusal's own words where there are any.
        ///   - code: The machine-readable family — see ``ScriptErrorCode``.
        ///   - source: The ``ScriptSource/name`` the error came from, when it is known.
        ///   - line: The 1-based line inside that source, when JavaScriptCore recorded one.
        ///   - column: The 1-based column, when JavaScriptCore recorded one.
        ///   - sourceLine: That line of the source, quoted verbatim and untrimmed.
        ///   - candidates: The nodes the refusal named, where it named any.
        public init(
            message: String,
            code: String,
            source: String? = nil,
            line: Int? = nil,
            column: Int? = nil,
            sourceLine: String? = nil,
            candidates: [NodeAddressCandidate] = []
        ) {
            self.message = message
            self.code = code
            self.source = source
            self.line = line
            self.column = column
            self.sourceLine = sourceLine
            self.candidates = candidates
        }

        /// The sentence to show a reader.
        public let message: String

        /// The machine-readable family: an ``Woodcase/EditingError/code`` for a refusal
        /// from the editing layer, one of ``ScriptErrorCode``'s own otherwise.
        public let code: String

        /// Which source the error came from — a file's path, or the name a text source
        /// was given. `nil` when the failure belongs to no one source.
        public let source: String?

        /// The 1-based line inside ``source``.
        public let line: Int?

        /// The 1-based column inside ``line``.
        public let column: Int?

        /// The source line itself, quoted verbatim so a report can show it under the
        /// message without re-reading the file.
        public let sourceLine: String?

        /// The nodes the refusal named — an ambiguous address's candidates, a missing
        /// one's near misses — as values rather than as prose inside ``message``.
        public let candidates: [NodeAddressCandidate]
    }

#endif
