//
//  CommandTransaction.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// ``Woodcase/PenFileTransaction`` as a verb opens it: the same read and write, with what
/// the read met said on standard error before the verb's own work runs.
///
/// Today that is the file's component loops (``ComponentLoopNote``), said even when the
/// verb then fails — a refused write still names the loop the file already holds. Every
/// verb that opens a file goes through here, so none can forget to.
enum CommandTransaction {
    /// ``Woodcase/PenFileTransaction/read(at:timeout:diagnostics:fonts:isolation:_:)``,
    /// saying what the read met first.
    ///
    /// - Parameters:
    ///   - url: The .pen file to read.
    ///   - diagnostics: A collector for the parse's own warnings, or `nil`.
    ///   - fonts: The font resolver the document settles through.
    ///   - isolation: The caller's actor, filled in by `#isolation`.
    ///   - body: The read.
    /// - Returns: The transaction's outcome.
    /// - Throws: Whatever the transaction or the body throws.
    @discardableResult
    static func read<Value: Sendable>(
        at url: URL,
        diagnostics: PenDiagnosticCollector? = nil,
        fonts: GoogleFontResolver? = nil,
        isolation: isolated (any Actor)? = #isolation,
        _ body: (EditableDocument) throws -> Value
    ) async throws -> PenFileTransaction.Outcome<Value> {
        try await PenFileTransaction.read(at: url, diagnostics: diagnostics, fonts: fonts, isolation: isolation) { document in
            ComponentLoopNote.say(document.readContext)
            return try body(document)
        }
    }

    /// ``Woodcase/PenFileTransaction/run(at:identity:log:timeout:effect:fonts:isolation:_:)``,
    /// saying what the read met first.
    ///
    /// - Parameters:
    ///   - url: The .pen file to edit.
    ///   - identity: The writer's name, or `nil` for the unattributed writer.
    ///   - effect: Whether to keep the result.
    ///   - fonts: The font resolver the document settles through.
    ///   - isolation: The caller's actor, filled in by `#isolation`.
    ///   - body: The edit.
    /// - Returns: The transaction's outcome.
    /// - Throws: Whatever the transaction or the body throws.
    @discardableResult
    static func run<Value: Sendable>(
        at url: URL,
        identity: String?,
        effect: WriteEffect = .commit,
        fonts: GoogleFontResolver? = nil,
        isolation: isolated (any Actor)? = #isolation,
        _ body: (EditableDocument, ActivityRecorder) throws -> Value
    ) async throws -> PenFileTransaction.Outcome<Value> {
        try await PenFileTransaction.run(
            at: url, identity: identity, effect: effect, fonts: fonts, isolation: isolation
        ) { document, recorder in
            ComponentLoopNote.say(document.readContext)
            return try body(document, recorder)
        }
    }
}
