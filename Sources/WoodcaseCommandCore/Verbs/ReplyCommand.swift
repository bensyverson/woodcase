//
//  ReplyCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase reply <file> <thread> "text"` — adds a message to a comment thread.
///
/// ```bash
/// woodcase reply design.pen Cm01 "Fixed: 44pt now. @ana" --as claude
/// ```
struct ReplyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reply",
        abstract: "Write: reply to a comment thread.",
        discussion: """
        An act verb. It writes one note at the document root carrying woodcase.type \
        comment, the author (--as, required), createdAt (now, in UTC to the second) and \
        replyTo: the thread's FIRST message, always — given a reply's id, the new reply \
        still threads under the message that started the conversation.

        The thread is any message's id, as `woodcase comments` lists them; anything that \
        is not a comment message is refused with the threads there are. The text is \
        markdown, as the last argument or from -F (`-F -` reads standard input).

        EXAMPLES
          woodcase reply design.pen Cm01 "Fixed: 44pt now. @ana" --as claude
          woodcase comments design.pen --mentions ana
        """
    )

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: ArgumentHelp("Any message of the thread: its first, or a reply.", valueName: "thread"))
    var thread: String

    @Argument(help: "The reply, as markdown. Or give it with -F.")
    var text: String?

    @Option(name: .customLong("id"), help: ArgumentHelp("The id to give the reply; one is minted otherwise.", valueName: "id"))
    var messageID: String?

    @Option(
        name: .customShort("F"),
        help: ArgumentHelp("The text, from a file. `-` reads standard input.", valueName: "file")
    )
    var textFile: String?

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Author>
    @OptionGroup var output: OutputOptions

    /// Adds the reply and prints its id and the thread's.
    func run() async throws {
        let url = try file.existingFile()
        let body = try CommentWrite.text(text, file: textFile)
        let author = try CommentWrite.author(identity.identity)
        let target = thread
        let id = messageID
        let date = Date()

        try await CommentWrite.run(
            self, file: url, identity: author, action: .reply, effect: preview.effect, json: output.json
        ) { document in
            let write = try PenComment.reply(body, to: target, author: author, at: date, id: id, in: document)
            return CommentWrite.Built(write: write, thread: write.threadID, createdAt: PenComment.createdAt(date))
        }
    }
}
