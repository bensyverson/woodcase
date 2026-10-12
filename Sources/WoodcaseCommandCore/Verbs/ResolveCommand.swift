//
//  ResolveCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase resolve <file> <thread> [--reopen]` — ends a comment thread, or takes it up
/// again.
///
/// ```bash
/// woodcase resolve design.pen Cm01 --as ana
/// woodcase resolve design.pen Cm01 --reopen --as ana
/// ```
struct ResolveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve",
        abstract: "Write: resolve a comment thread, or --reopen it.",
        discussion: """
        An act verb. It sets woodcase.state on the thread's first message — resolved, \
        or open with --reopen — and touches nothing else. Only a comment thread has a \
        state; the thread is any message's id, a reply standing for its thread. A thread \
        already in that state is left alone: the answer says so and exits 0.

        --rev guards the first message: the rev `woodcase comments --json` prints for it.

        EXAMPLES
          woodcase resolve design.pen Cm01 --as ana
          woodcase resolve design.pen Cm01 --reopen --as ana
        """
    )

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: ArgumentHelp("Any message of the thread: its first, or a reply.", valueName: "thread"))
    var thread: String

    @Flag(name: .long, help: "Set the thread open again instead of resolved.")
    var reopen: Bool = false

    @OptionGroup var revision: RevisionOption
    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Sets the thread's state and prints it.
    func run() async throws {
        let url = try file.existingFile()
        let state: PenPostIt.State = reopen ? .open : .resolved
        let target = thread

        try await CommentWrite.run(
            self, file: url, identity: identity.identity, action: reopen ? .open : .resolved, rev: revision.rev,
            effect: preview.effect, json: output.json
        ) { document in
            let write = try PenComment.setState(state, of: target, in: document)
            let threadID = try write?.threadID ?? PenComment.threadID(of: target, in: document)
            return CommentWrite.Built(write: write, thread: threadID)
        }
    }
}
