//
//  ScriptThrow.swift
//  WoodcaseScripting
//

#if canImport(JavaScriptCore)

    import Foundation
    import Woodcase

    /// A refusal on its way from Swift into the script, already in the shape a
    /// `WoodcaseError` is built from.
    ///
    /// The host raises one of these rather than assembling a `JSValue` at every throw
    /// site: the sentence, the code and the candidates are decided where the failure is,
    /// and the crossing happens once, in ``ScriptRunner/raise(_:in:)``.
    struct ScriptThrow: Error {
        /// Names a refusal.
        ///
        /// - Parameters:
        ///   - message: The sentence, in the house convention: what was addressed, what
        ///     happened, and the remedy after ` — `.
        ///   - code: The ``ScriptError/code`` a script reads off `err.code`.
        ///   - candidates: The nodes the sentence named, where it named any.
        init(message: String, code: String, candidates: [NodeAddressCandidate] = []) {
            self.message = message
            self.code = code
            self.candidates = candidates
        }

        /// The sentence.
        let message: String

        /// The machine-readable family.
        let code: String

        /// The nodes the sentence named.
        let candidates: [NodeAddressCandidate]

        /// The refusal for an editing failure, in the words the verb would have used.
        ///
        /// The whole point of routing through ``Woodcase/BatchErrorMessage``: a `doc.get`
        /// that cannot resolve an address says exactly what `woodcase get` says, remedy
        /// and all, so a caller who learned one has learned the other.
        ///
        /// - Parameters:
        ///   - error: The failure, usually an ``Woodcase/EditingError``.
        ///   - document: The document it happened in, for name paths.
        ///   - remedy: Which grammar the remedy is written in.
        /// - Returns: The refusal, with the editing error's own code and candidates when
        ///   it has them.
        ///
        /// Both halves of the editing vocabulary are routed: an ``Woodcase/EditingError``
        /// carries its ``Woodcase/EditingError/code`` and candidates, and a
        /// ``Woodcase/BatchError`` — the grammar's own refusals, which a write member
        /// raises as readily as a batch line does — carries
        /// ``Woodcase/BatchError/code``. Anything else is the host's own bug and says so.
        static func editing(
            _ error: any Error,
            in document: EditableDocument,
            remedy: RemedyDialect
        ) -> ScriptThrow {
            let editing = error as? EditingError
            return ScriptThrow(
                message: BatchErrorMessage.describe(error, in: document, dialect: remedy),
                code: editing?.code
                    ?? (error as? BatchError)?.code
                    ?? ScriptErrorCode.scriptError,
                candidates: editing?.candidates ?? []
            )
        }
    }

#endif
