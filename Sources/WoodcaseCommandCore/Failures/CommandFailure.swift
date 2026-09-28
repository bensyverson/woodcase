//
//  CommandFailure.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// A message for the reader and an exit code for the shell: the one place a library
/// error becomes both.
///
/// Every verb funnels its failures through ``describing(_:in:editing:)`` (inside a
/// transaction, where the document can turn ids into name paths) or
/// ``describing(_:editing:)`` (outside one). Nothing else decides an exit code, so the
/// house table is honoured the same way by ten different verbs written by ten
/// different hands.
///
/// ```swift
/// func run() async throws {
///     let url = try file.existingFile()
///     try await runReportingFailures(editing: url) {
///         try await PenFileTransaction.run(at: url, identity: identity.identity) { document, recorder in
///             do { … } catch { throw CommandFailure.describing(error, in: document, editing: url) }
///         }
///     }
/// }
/// ```
///
/// The inner `catch` is what buys the *best* message for an ``EditingError``:
/// ``BatchErrorMessage`` needs the document to turn a node id into a name path, and the
/// document only exists inside the transaction's body. A failure wrapped there passes
/// through the outer mapper untouched. Both mappers still render the whole sentence,
/// remedy and all: a ``BatchError`` never needs a document — every case already carries
/// its address or path as text — and an ``EditingError`` raised where none is at hand
/// is rendered against an empty one, which names its nodes by the id as typed, exactly
/// as a node missing from the real document is already named.
///
/// Both mappers ask ``BatchErrorMessage`` for the sentence in ``RemedyDialect/command(file:)``,
/// so a refusal that says "write it as `{"op":"override",…}`" inside a batch says "run
/// `woodcase override …`" at a prompt. The sentence itself lives once, in the library.
///
/// ## The table
///
/// | Error | Code |
/// |---|---|
/// | ``PenFileError/cannotOpen(url:reason:)``, ``PenFileError/unreadable(url:reason:)``, ``PenFileError/writeFailed(url:reason:)`` on the .pen file | 4 |
/// | ``PenFileError/lockTimeout(url:timeout:)`` on the .pen file | 3 |
/// | any ``PenFileError`` naming a *different* file — the activity log | 5 |
/// | ``PenParserError`` — the bytes are not a .pen document this build can read, rendered by ``ParserFailureMessage`` | 4 |
/// | ``PenFormatWriteRefusal`` — a write to a file of another major version, which is read-only, rendered by ``ReadOnlyFormatMessage`` | 4 |
/// | ``EditingError/revisionConflict(nodeID:expected:actual:)``, ``BatchError/documentRevisionConflict(expected:actual:)`` | 3 |
/// | ``BatchError/guardConflict(node:address:expected:actual:writer:)``, ``BatchError/guardNodeMissing(node:)`` — a premise moved | 3 |
/// | every other ``EditingError`` and ``BatchError`` | 2 |
/// | ArgumentParser's `ValidationError`, and a malformed `--theme` pin | 2 |
/// | `Render.RenderError`, ``PNGEncoder/EncodingError``, ``PDFExporter/ExportError`` — the pipeline ran but could not produce the image | 4 |
/// | anything else | 5 |
///
/// The last row is deliberate: an error this table does not recognise is not a *clean
/// negative* (1), which scripts branch on, and not a *usage* error (2), which would
/// blame an invocation that may have been perfectly good.
struct CommandFailure: Error, Friendly, CustomStringConvertible {
    /// Creates a failure.
    ///
    /// - Parameters:
    ///   - message: The sentence to print on standard error.
    ///   - exitCode: The house exit code to end the process with.
    init(message: String, exitCode: ExitCode) {
        self.message = message
        status = exitCode.rawValue
    }

    /// The sentence printed on standard error.
    let message: String

    /// The raw exit status. ``exitCode`` is the typed form; this is what is stored, so
    /// the failure stays `Codable` without ArgumentParser's type having to be.
    let status: Int32

    /// The house exit code this failure ends the process with.
    var exitCode: ExitCode {
        ExitCode(status)
    }

    /// The message.
    var description: String {
        message
    }

    // MARK: - Mapping

    /// Maps a failure raised where no document is at hand.
    ///
    /// An ``EditingError`` that reaches here is rendered against ``noDocument``, so it
    /// keeps its sentence and its remedy and loses only the name path: wrap one inside
    /// the transaction with ``describing(_:in:editing:)`` to have its nodes named by
    /// path as well.
    ///
    /// - Parameters:
    ///   - error: The failure.
    ///   - file: The .pen file the verb was working on, when there is one. This is how
    ///     a failure to append to the *activity log* is told apart from a failure to
    ///     write the document: the log is a ``PenFileError`` naming another file, and
    ///     the edit is already on disk by the time it is raised.
    /// - Returns: The message and exit code to end the command with.
    static func describing(_ error: any Error, editing file: URL? = nil) -> CommandFailure {
        switch error {
        case let failure as CommandFailure:
            failure
        case let fileError as PenFileError:
            describing(fileError, editing: file)
        case let parser as PenParserError:
            CommandFailure(message: ParserFailureMessage.describe(parser), exitCode: .targetFailure)
        case let refusal as PenFormatWriteRefusal:
            CommandFailure(message: ReadOnlyFormatMessage.describe(refusal), exitCode: .targetFailure)
        case let validation as ValidationError:
            CommandFailure(message: "\(validation)", exitCode: .usage)
        case let pin as ThemePinParser.PinError:
            CommandFailure(message: "\(pin)", exitCode: .usage)
        case let render as Render.RenderError:
            CommandFailure(message: "\(render)", exitCode: .targetFailure)
        case let image as PNGEncoder.EncodingError:
            CommandFailure(message: "\(image)", exitCode: .targetFailure)
        case let pdf as PDFExporter.ExportError:
            CommandFailure(message: "\(pdf)", exitCode: .targetFailure)
        case let editing as EditingError:
            CommandFailure(
                message: BatchErrorMessage.describe(editing, in: noDocument, dialect: dialect(editing: file)),
                exitCode: exitCode(for: editing)
            )
        case let batch as BatchError:
            CommandFailure(
                message: BatchErrorMessage.describe(batch, dialect: dialect(editing: file)),
                exitCode: exitCode(for: batch)
            )
        case is CocoaError, is URLError:
            CommandFailure(message: error.localizedDescription, exitCode: .environment)
        default:
            CommandFailure(message: "\(error)", exitCode: .environment)
        }
    }

    /// Maps a failure raised inside a transaction, where ids can become name paths.
    ///
    /// - Parameters:
    ///   - error: The failure.
    ///   - document: The document the operation ran against, for
    ///     ``BatchErrorMessage/describe(_:in:dialect:)``.
    ///   - file: The .pen file the verb was working on, when there is one.
    /// - Returns: The message and exit code to end the command with.
    static func describing(
        _ error: any Error,
        in document: EditableDocument,
        editing file: URL? = nil
    ) -> CommandFailure {
        switch error {
        case let failure as CommandFailure:
            failure
        case let editing as EditingError:
            CommandFailure(
                message: BatchErrorMessage.describe(editing, in: document, dialect: dialect(editing: file)),
                exitCode: exitCode(for: editing)
            )
        case let batch as BatchError:
            CommandFailure(
                message: BatchErrorMessage.describe(batch, in: document, dialect: dialect(editing: file)),
                exitCode: exitCode(for: batch)
            )
        default:
            describing(error, editing: file)
        }
    }

    // MARK: - Private

    /// The stand-in document a refusal is rendered against when the real one is out of
    /// reach — outside a transaction, or before one has opened the file.
    ///
    /// Every ``EditingError`` case that wants a document wants it only to turn a node
    /// id into a name path, and ``BatchErrorMessage`` already renders a node that is
    /// not in the document as the id exactly as typed. An empty document is therefore
    /// the honest stand-in: the statement and its remedy come out whole, and the only
    /// thing missing is a name path the caller never had.
    ///
    /// A fresh one per call rather than a shared instance. ``EditableDocument`` is not
    /// `Sendable` — it belongs to whoever made it — so one held in a `static let` would
    /// be shared mutable state across every isolation domain that ever printed a
    /// refusal. Building an empty one is a handful of empty dictionaries.
    private static var noDocument: EditableDocument {
        EditableDocument(from: PenDocument(children: []))
    }

    /// The dialect a verb's reader is standing in: always the shell, never a batch file.
    ///
    /// This is what retires the CLI's own re-phrasing of the three refusals whose
    /// remedy used to be written twice — once in batch grammar in the library, once in
    /// shell words in the command layer. There is one copy of each sentence now, and
    /// the dialect chooses its tail.
    private static func dialect(editing file: URL?) -> RemedyDialect {
        .command(file: file?.path ?? "<file>")
    }

    /// Maps a file error, telling the .pen file apart from the activity log.
    private static func describing(_ error: PenFileError, editing file: URL?) -> CommandFailure {
        if let file, error.url.standardizedFileURL != file.standardizedFileURL {
            return CommandFailure(message: logMessage(error, editing: file), exitCode: .environment)
        }
        switch error {
        case .lockTimeout:
            return CommandFailure(
                message: "\(error). Retry, or find the holder with `lsof \(error.url.path)`.",
                exitCode: .conflict
            )
        case .cannotOpen, .unreadable, .writeFailed:
            return CommandFailure(message: "\(error)", exitCode: .targetFailure)
        }
    }

    /// The sentence for a failure to append to the activity log.
    ///
    /// The transaction appends *after* the .pen file is committed, so this failure
    /// never means the edit was lost — and a message that did not say so would send
    /// the reader looking for damage that is not there.
    ///
    /// A denial that ``SandboxDenial`` recognises gets its sentence in place of the
    /// usual "check $WOODCASE_HOME": that remedy assumes the path is merely wrong,
    /// which is not the problem when the environment itself refuses the write.
    private static func logMessage(_ error: PenFileError, editing file: URL) -> String {
        if SandboxDenial.matches(error) {
            return """
            \(SandboxDenial.sentence(forbidding: "writing the activity log \(error.url.path)")) \
            The edit to \(file.path) is on disk; only its log entry was lost.
            """
        }
        let cause = switch error {
        case let .cannotOpen(url, reason), let .writeFailed(url, reason):
            "Cannot write the activity log \(url.path): \(reason)."
        case let .unreadable(url, reason):
            "The activity log \(url.path) is not readable: \(reason)."
        case let .lockTimeout(url, _):
            "The activity log \(url.path) is held by another process."
        }
        let directory = error.url.deletingLastPathComponent().path
        return "\(cause) The edit to \(file.path) is on disk; only its log entry was lost. "
            + "Next: `mkdir -p \(directory)`, or set $WOODCASE_HOME to a directory you can write."
    }

    /// A stale revision is a conflict; everything else an edit refuses is usage.
    private static func exitCode(for error: EditingError) -> ExitCode {
        if case .revisionConflict = error { return .conflict }
        return .usage
    }

    /// The world having moved is a conflict; everything else a batch refuses is usage.
    ///
    /// A stale document revision and a failed ``BatchGuard`` are both "what you read is
    /// no longer true", which is the conflict row. A guard that names a tag or a line
    /// with nothing to pin is a malformed invocation, which is not.
    private static func exitCode(for error: BatchError) -> ExitCode {
        switch error {
        case .documentRevisionConflict, .guardConflict, .guardNodeMissing:
            .conflict
        case .malformedLine, .malformedRow, .unnamedNode, .literalRootOverridesKey,
             .replacementIDMismatch, .setInsideInstance, .structureInsideSlot,
             .overrideOutsideInstance,
             .overrideWithoutProperties, .parentInsideInstance, .guardOnTag,
             .guardWithoutTarget, .copyPathNotInSource, .parameterPathNotFound,
             .emptyCopyRows, .copyTagWithRows:
            .usage
        }
    }
}
