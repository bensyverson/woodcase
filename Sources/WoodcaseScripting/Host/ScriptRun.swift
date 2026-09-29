//
//  ScriptRun.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import Woodcase

    /// Everything one script run says back.
    ///
    /// One timeline rather than separate arrays, because *what was printed before which
    /// write* is part of the answer: a caller rendering a transcript walks ``events`` in
    /// order and needs no second sort.
    ///
    /// ```swift
    /// let run = ScriptHost.run([.text("doc.lint().length", name: "<argv>")], over: document)
    /// run.result        // .int(0)
    /// run.commit        // .unchanged — this run wrote nothing
    /// run.error?.message
    /// ```
    public struct ScriptRun: Friendly {
        /// Records a run.
        ///
        /// - Parameters:
        ///   - events: The timeline, in the order the run produced it.
        ///   - result: The completion value of the last source, or `nil`.
        ///   - documentRevision: The document's revision when the run ended.
        ///   - commit: How the run ended for the file.
        ///   - error: Why it ended early, or `nil` when it ran to the end.
        public init(
            events: [Event],
            result: AnyCodable?,
            documentRevision: String,
            commit: Commit,
            error: ScriptError?
        ) {
            self.events = events
            self.result = result
            self.documentRevision = documentRevision
            self.commit = commit
            self.error = error
        }

        /// What happened, in order.
        public let events: [Event]

        /// The completion value of the **last** source, as JSON.
        ///
        /// A script hands its caller a structured answer by ending in an expression —
        /// `({ rows: doc.tree('list'), lint: doc.lint() })` — with no wrapping function
        /// and no top-level `return`, so a one-liner from stdin works unchanged. The
        /// value crosses through `JSON.stringify` in the script's own context; a
        /// function, a Promise, a symbol or a cycle cannot cross, so the result is `nil`
        /// and an ``Event/warning(_:)`` says which it was — never a silent
        /// `[object Object]`.
        ///
        /// `nil` also for a script whose last statement is not an expression, which is
        /// ordinary and produces no warning.
        public let result: AnyCodable?

        /// ``Woodcase/EditableDocument/documentRevision`` when the run ended.
        public let documentRevision: String

        /// How the run ended for the file on disk.
        public let commit: Commit

        /// Why the run ended early, or `nil` when it reached the end of the last source.
        public let error: ScriptError?

        // MARK: - Event

        /// One thing that happened during a run.
        public enum Event: Friendly {
            /// A write: which member of `doc` made it, and that verb's own echo — id,
            /// path, revision, the subtree that came into being, and the divergences.
            ///
            /// One per call to a write member of `doc`, recorded as it happens and in the
            /// same order the script made them. It carries no settled rect on purpose: a
            /// write invalidates layout, and a rect per write would force a settle per
            /// write. Geometry is asked for through `doc.tree` when the script wants it.
            ///
            /// The member is on the event rather than inside the report because a
            /// ``Woodcase/WriteReport`` says what was *touched* and never what touched it:
            /// `doc.override` reports the instance, so a copy and the three overrides that
            /// fill it would otherwise print four rows nobody can tell apart.
            case write(member: ScriptWriteMember, WriteReport)

            /// A `console` line, already rendered: several arguments joined by spaces,
            /// objects as JSON.
            case log(level: ScriptLogLevel, text: String)

            /// Something the run wants said that is not a refusal — a completion value
            /// that could not cross, a font that fell back.
            case warning(String)

            /// A root overlap this run created, as the finding `lint` reports for the
            /// same fact.
            ///
            /// One per newly overlapping pair, recorded once at the end of the run rather
            /// than per write: a write that breaks the layout and a later one that
            /// repairs it net out to nothing, which is `apply`'s rule and has to be this
            /// one too. A run that ended in an error records none — nothing was written,
            /// so there is no overlap on disk to warn about.
            ///
            /// It carries the finding rather than a rendered line so a caller decides how
            /// to show it: ``Woodcase/LintFormatter/text(_:)`` gives the line every verb
            /// prints, and an editor can put the same fact next to the artboard.
            case overlap(LintFinding)
        }

        // MARK: - Commit

        /// How a run ended for the file on disk.
        ///
        /// ## What the host itself can answer
        ///
        /// The host holds a document, not a file: it never encodes, never compares bytes
        /// and never writes. So it answers for *the script* — ``wrote`` when at least one
        /// write event happened, ``unchanged`` when none did, ``rolledBack`` when the run
        /// ended in an uncaught error, whether or not writes landed on the document
        /// first. That last one is not a guess: a run is meant to be wrapped in one
        /// ``Woodcase/PenFileTransaction``, and a transaction whose body throws writes
        /// nothing and appends nothing.
        ///
        /// ## What the verb maps over it
        ///
        /// A caller that owns the transaction knows two things the host cannot, and maps
        /// its ``Woodcase/PenFileTransaction/Outcome/commit`` over this one where they
        /// differ: ``previewed``, which is `--dry-run` and a decision made before the
        /// script started; and ``unchanged`` for a script that wrote and then wrote back —
        /// the document encodes to the bytes it was handed, so nothing was written after
        /// all. The host reports ``wrote`` for that run, because the script did write.
        public enum Commit: String, Friendly, CaseIterable {
            /// The run wrote, and the new bytes are on disk.
            case wrote

            /// The run made no change — a read-only script, or writes that canceled out.
            case unchanged

            /// `--dry-run`: everything ran and nothing was written, on purpose.
            case previewed

            /// An uncaught error, a timeout or a refusal: nothing was written, and the
            /// file is byte for byte what it was.
            case rolledBack
        }
    }

#endif
