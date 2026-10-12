//
//  DocumentLinter+NoteState.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/noteState`` check.
///
/// Only comments are open or resolved, and a prompt's state is where its run stands
/// (Ben's ruling, 2026-10-11, Penumbra's notes design decision 8). A plain note's `state`
/// — in either spelling, from Ben's files written before the ruling — is read but drawn
/// as nothing. `woodcase migrate` does not drop it: the value is the author's, and it may
/// say the note should have been a comment, so the notice names it instead, as a legacy
/// `kind` is left as written.
extension DocumentLinter {
    /// A note, as the file stores it, that is neither a comment nor a prompt and carries a
    /// `state`.
    ///
    /// A row inside an instance is skipped: its metadata is the component's, reported once
    /// on the component's own node.
    ///
    /// - Parameters:
    ///   - row: The row, for the finding's id and path.
    ///   - context: The lint context, for the node as authored.
    /// - Returns: Zero or one finding, naming the state's value.
    static func noteState(_ row: TreeRow, in context: Context) -> [LintFinding] {
        guard !row.id.contains(NodeAddress.separator),
              let node = context.authored(row), case .note = node.kind,
              let metadata = PenPostIt.Metadata(node), metadata.type != .valid(.comment),
              let state = metadata.state
        else { return [] }
        let value = switch state {
        case let .valid(state): state.rawValue
        case let .unrecognized(text): text
        }
        return [finding(
            .noteState, row,
            "keeps a state (`\(value)`), which only a comment has, so it is not drawn. Remove "
                + "`metadata.\(PenMetadata.woodcaseNamespace).state`, or make the note a comment "
                + "(`woodcase.type: comment`) if it is one."
        )]
    }
}
