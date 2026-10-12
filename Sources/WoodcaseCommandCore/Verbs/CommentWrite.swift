//
//  CommentWrite.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// What `comment`, `reply` and `resolve` share: take the message's text, open the file
/// under the writer's name, apply the one edit ``Woodcase/PenComment`` builds, and answer
/// with ``CommentWriteReport``.
///
/// The decisions — what a message carries, which message a reply names, when a state
/// change is no change — are ``Woodcase/PenComment``'s; this only wires them to the
/// transaction, so each edit goes through the ``Woodcase/ActivityRecorder`` and is
/// logged and undoable like every other write.
enum CommentWrite {
    /// One verb's write, built against the open document.
    struct Built {
        /// The edit to apply, or `nil` when there is nothing to change.
        var write: PenComment.Write?
        /// What to report: the thread and message, when no write carries them.
        var thread: String
        /// When the new message was written, in UTC.
        var createdAt: String?
    }

    /// The message's text: the argument, or the file `-F` names, never both.
    ///
    /// A trailing newline — a heredoc or an editor always leaves one — is dropped.
    ///
    /// - Parameters:
    ///   - inline: The text given as an argument.
    ///   - file: The `-F` path; `-` reads standard input.
    /// - Returns: The text.
    /// - Throws: A usage failure when both or neither is given, or the file is empty.
    static func text(_ inline: String?, file: String?) throws -> String {
        let text: String
        switch (inline, file) {
        case (.some, .some):
            throw CommandFailure(
                message: "The text comes from the last argument or from -F, not both. Drop one.", exitCode: .usage
            )
        case let (inline?, nil):
            text = inline
        case let (nil, path?):
            text = try String(decoding: InputFile.data(at: path), as: UTF8.self)
        case (nil, nil):
            text = ""
        }
        let trimmed = String(text.reversed().drop { $0.isNewline }.reversed())
        guard !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CommandFailure(message: PenComment.WriteError.emptyMessage.message, exitCode: .usage)
        }
        return trimmed
    }

    /// The author `--as` names, refusing without one.
    ///
    /// - Parameter identity: The resolved `--as` / `$WOODCASE_AS`.
    /// - Returns: The name.
    /// - Throws: A usage failure when there is none.
    static func author(_ identity: String?) throws -> String {
        guard let identity else {
            throw CommandFailure(
                message: "A comment needs its author: pass --as <name>, or set $\(Identity.environmentVariable). "
                    + "The name is stamped on the message as woodcase.author.",
                exitCode: .usage
            )
        }
        return identity
    }

    /// Opens the file, builds and applies the write, and prints the report.
    ///
    /// - Parameters:
    ///   - command: The verb, which reports failures the house way.
    ///   - file: The .pen file.
    ///   - identity: Who the edit is logged as.
    ///   - action: What the verb does, for the report.
    ///   - rev: The revision of the thread's first message the caller last observed.
    ///   - effect: Whether to keep the result.
    ///   - json: Whether `--json` was passed.
    ///   - build: Builds the write against the open document.
    /// - Throws: The failure, mapped to its house exit code.
    static func run(
        _ command: some ParsableCommand,
        file: URL,
        identity: String?,
        action: CommentWriteReport.Action,
        rev: String? = nil,
        effect: WriteEffect,
        json: Bool,
        build: @escaping (EditableDocument) throws -> Built
    ) async throws {
        try await command.runReportingFailures(editing: file) {
            let outcome = try await CommandTransaction.run(
                at: file, identity: identity, effect: effect, fonts: .shared
            ) { document, recorder in
                do {
                    let built = try build(document)
                    var report = CommentWriteReport(
                        action: action, thread: built.write?.threadID ?? built.thread,
                        message: built.write?.messageID ?? built.thread, createdAt: built.createdAt,
                        unchanged: built.write == nil, dryRun: effect == .dryRun
                    )
                    if let write = built.write {
                        try recorder.apply(write.operation, expecting: rev.map { [write.threadID: $0] } ?? [:])
                        if effect != .dryRun {
                            report.rev = document.revision(of: write.messageID)
                            report.documentRevision = document.documentRevision
                        }
                    }
                    return try report.rendered(json: json)
                } catch let refusal as PenComment.WriteError {
                    throw CommandFailure(message: refusal.message, exitCode: .usage)
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: file)
                }
            }
            OutsideWriteNote.report(outcome, json: json)
            print(outcome.value)
        }
    }
}
