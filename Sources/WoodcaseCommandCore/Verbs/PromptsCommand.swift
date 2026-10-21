//
//  PromptsCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase prompts <file>` — a read verb listing the Run queue: each prompt, where its
/// run stands, and who requested it, so an agent can claim queued work.
///
/// ```bash
/// woodcase prompts design.pen --state queued --json
/// woodcase set design.pen Pr01 note.state=running --rev <rev> --as claude
/// ```
struct Prompts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prompts",
        abstract: "Read: the prompts in a .pen file and the Run queue — state and requestedBy.",
        discussion: """
        A read verb: it takes a shared lock and writes nothing.

        Run queues work in the file. Pressing Run on a prompt sets \
        `note.state` to queued and `note.requestedBy` to whoever \
        pressed it; an agent claims the work by writing running, answers in a comment \
        thread anchored to the prompt, and writes done. Each row is the state (`-` for \
        a prompt never run), who requested it, the model it names, its first line, and \
        its id, always last. The header carries the document's revision; --json carries \
        each prompt's own rev and its whole content.

        TO CLAIM queued work, quote the prompt's rev so two agents cannot both take it — \
        the second write fails with exit 3:

          woodcase prompts design.pen --state queued --json
          woodcase set design.pen Pr01 note.state=running \\
            --rev <rev> --as claude

        --state takes queued, running, done or all; --requested-by keeps one \
        requester's prompts, refusing a misspelling of a name the file holds. An empty \
        listing prints nothing and exits 1.
        """
    )

    @Argument(help: "The .pen file to read.")
    var file: PenFilePath

    @Option(name: .long, help: "Keep prompts whose run is in this state. Default: all.")
    var state: PenNoteBoard.PromptQuery.State?

    @Option(name: .customLong("requested-by"), help: "Keep prompts this identity pressed Run on.")
    var requestedBy: String?

    @OptionGroup var output: OutputOptions

    /// Reads the file and prints the prompts the filters keep.
    func run() async throws {
        let url = try file.existingFile()
        let json = output.json
        let state = state
        try await NoteBoardRead.run(self, file: url, identities: [("--requested-by", requestedBy)]) { board, names, revision in
            let prompts = board.prompts(PenNoteBoard.PromptQuery(state: state, requestedBy: names["--requested-by"]))
            let text = json
                ? try PenNoteBoardFormatter.json(PenNoteBoard.PromptsReport(revision: revision, prompts: prompts))
                : PenNoteBoardFormatter.text(prompts: prompts, revision: revision)
            return NoteBoardRead.Listing(count: prompts.count, text: text)
        }
    }
}
