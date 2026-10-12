//
//  NotesCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase notes <file>` — a read verb listing the post-its: plain notes, not comment
/// messages or prompts.
///
/// ```bash
/// woodcase notes board.pen
/// woodcase notes board.pen --author claude --json
/// ```
struct Notes: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "notes",
        abstract: "Read: the post-its in a .pen file — author, tint, size and first line.",
        discussion: """
        A read verb: it takes a shared lock and writes nothing.

        A post-it is a plain `note`: one that is not a comment message (those are \
        `woodcase comments`) and not a prompt (`woodcase prompts`). A note has no state \
        and no kind; what tells notes apart is who wrote them, their paper and their \
        words. Each row is the author, the tint (`-` is Post-it yellow), the size the \
        note lays out at — it grows to fit its text — the first line of its markdown, \
        and the id, always last. The header carries the document's revision; --json \
        carries each note's own rev and its whole content.

        Metadata is read under `metadata.woodcase`, old spellings included. An empty \
        listing prints nothing and exits 1.

          woodcase notes board.pen --author claude
        """
    )

    @Argument(help: "The .pen file to read.")
    var file: PenFilePath

    @Option(name: .long, help: "Keep only this author's notes. A misspelling of a name the file holds is refused.")
    var author: String?

    @OptionGroup var output: OutputOptions

    /// Reads the file and prints its notes.
    func run() async throws {
        let url = try file.existingFile()
        let json = output.json
        try await NoteBoardRead.run(self, file: url, identities: [("--author", author)]) { board, names, revision in
            let notes = board.notes(PenNoteBoard.NoteQuery(author: names["--author"]))
            let text = json
                ? try PenNoteBoardFormatter.json(PenNoteBoard.NotesReport(revision: revision, notes: notes))
                : PenNoteBoardFormatter.text(notes: notes, revision: revision)
            return NoteBoardRead.Listing(count: notes.count, text: text)
        }
    }
}
