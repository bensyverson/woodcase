//
//  CommentsCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase comments <file>` — a read verb listing comment threads, so an agent can
/// find the ones that mention it.
///
/// ```bash
/// woodcase comments design.pen --mentions claude
/// woodcase comments design.pen --state resolved --json
/// ```
struct Comments: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "comments",
        abstract: "Read: the comment threads in a .pen file, with replies, anchor and state.",
        discussion: """
        A read verb: it takes a shared lock and writes nothing.

        A comment is a note, one per message (`metadata.woodcase.type: comment`), at \
        the document root. The first message carries the thread's anchor — the node it \
        is about and the point on it — and its state, open or resolved; each reply \
        names the first message in `woodcase.replyTo`. The listing has one row per \
        message: the first message's row leads with the thread's state and anchor \
        (`Btn01 @12,4`), each reply's with `reply`, then the author, the names it \
        @mentions, its first line, and its id, always last. A reply whose first message \
        is gone leads with `⚠ orphan`. The header carries the document's revision; \
        --json nests each thread's messages, with each message's rev and whole content.

        FILTERS combine. --mentions keeps threads in which any message mentions the \
        name (with or without its @), --author threads in which they wrote any \
        message, --state open, resolved or all. With --mentions the state defaults to \
        open, so `--mentions claude` is the work waiting on claude; without it, every \
        thread is listed. A name close to one the file holds but not exactly it is \
        refused as a misspelling; an empty listing prints nothing and exits 1.

          woodcase comments design.pen --mentions claude
          woodcase get design.pen Cm01                 # the whole first message
        """
    )

    @Argument(help: "The .pen file to read.")
    var file: PenFilePath

    @Option(name: .long, help: "Keep threads that @mention this identity; open ones unless --state says otherwise.")
    var mentions: String?

    @Option(name: .long, help: "Keep threads in this state. Default: open with --mentions, all without.")
    var state: PenNoteBoard.CommentQuery.State?

    @Option(name: .long, help: "Keep threads this identity wrote any message in.")
    var author: String?

    @OptionGroup var output: OutputOptions

    /// Reads the file and prints the threads the filters keep.
    func run() async throws {
        let url = try file.existingFile()
        let json = output.json
        let state = state
        try await NoteBoardRead.run(
            self, file: url, identities: [("--mentions", mentions), ("--author", author)]
        ) { board, names, revision in
            let query = PenNoteBoard.CommentQuery(mentions: names["--mentions"], state: state, author: names["--author"])
            let threads = board.threads(query)
            let text = json
                ? try PenNoteBoardFormatter.json(PenNoteBoard.CommentsReport(revision: revision, threads: threads))
                : PenNoteBoardFormatter.text(threads: threads, revision: revision)
            return NoteBoardRead.Listing(count: threads.count, text: text)
        }
    }
}
