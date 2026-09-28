//
//  RemedyDialect.swift
//  Woodcase
//

import Foundation

/// The grammar a refusal's *remedy* is written in.
///
/// Every message ``BatchErrorMessage`` produces ends with the next thing to do, and
/// that next thing depends entirely on where the reader is standing. Someone holding a
/// batch file wants the JSONL to write; someone at a shell prompt wants the `woodcase`
/// command to run. The statement — what was addressed and what happened — is the same
/// either way, so only the tail is switched, and it is switched here rather than by
/// re-writing the sentence a second time somewhere downstream.
///
/// ```swift
/// BatchErrorMessage.describe(error, in: document)                              // batch
/// BatchErrorMessage.describe(error, in: document, dialect: .command(file: path)) // shell
/// NameInUse.variable(name, in: document).sentence(in: .script)                 // a script
/// ```
public enum RemedyDialect: Friendly {
    /// Inside a batch file: the remedy is the line to write.
    case batch

    /// At a shell prompt, against this .pen file: the remedy is the command to run.
    ///
    /// - Parameter file: The path a suggested command would be given, printed verbatim
    ///   so the reader can paste the whole line.
    case command(file: String)

    /// Inside a JavaScript program: the remedy is the argument to pass.
    ///
    /// A script has no `--force` and no shell to run a second command in, so wherever a
    /// remedy is spelled differently for it — `{ force: true }` rather than `--force` —
    /// this is the case that says so. Everywhere else it takes ``batch``'s wording,
    /// because a script's writes *are* batch lines and the JSON it would have to correct
    /// is the JSON a batch file holds.
    case script

    /// The .pen file a command-dialect remedy names.
    ///
    /// Batch dialect has no file — a batch line does not know which document it will be
    /// applied to — so it answers with the placeholder a reader would substitute. Batch
    /// remedies do not name commands, so the value is only ever a fallback.
    ///
    /// Public because a host that renders a remedy of its own — the script host's root
    /// overlap warning — holds the dialect and has nothing else to name the file with.
    public var file: String {
        switch self {
        case .batch, .script: "<file>"
        case let .command(file): file
        }
    }
}
