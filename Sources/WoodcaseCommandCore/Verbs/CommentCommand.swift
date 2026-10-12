//
//  CommentCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase comment <file> [<node>] [--at x,y] "text"` — starts a comment thread, so an
/// agent never writes the comment keys by hand.
///
/// ```bash
/// woodcase comment design.pen Card/Button --at 12,4 "Too tall, @ana?" --as claude
/// woodcase comment design.pen --at 900,40 "Room for a legend here" --as claude
/// ```
struct CommentCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "comment",
        abstract: "Write: start a comment thread on a node, or on the canvas.",
        discussion: """
        An act verb. It writes one note at the document root — a comment is a note, \
        one per message — carrying woodcase.type comment, the author (--as, required), \
        createdAt (now, in UTC to the second), state open, and the anchor: the node \
        and the point on it the bubble marks. The note is placed past every root, so \
        it never lands on an artboard in Pen.

        THE POINT is --at x,y, in the node's own coordinates — points from its top-left \
        corner — so the bubble moves and rotates with the node; it defaults to 0,0. The \
        node is any address: a name path, an id, or a path into a component instance \
        (stored as the expanded id path, instance/child). Give no node, or --canvas, and \
        x and y are page coordinates: a comment on the empty canvas, which needs --at.

        THE TEXT is markdown — @mentions included — as the last argument, or from a file \
        with -F (`-F -` reads standard input). The answer leads with the thread's id; \
        `woodcase reply` and `woodcase resolve` take it, and `woodcase comments` lists \
        the thread.

        \(AddressArgument.addressForms)

        EXAMPLES
          woodcase comment design.pen Card/Button --at 12,4 "Too tall, @ana?" --as claude
          woodcase comment design.pen --at 900,40 "Room for a legend" --as claude
        """
    )

    @Argument(help: ArgumentHelp("The .pen file to edit.", valueName: "file"))
    var file: PenFilePath

    @Argument(help: ArgumentHelp("The node to comment on (omit for the canvas), then the text.", valueName: "[node] text"))
    var words: [String] = []

    @Option(name: .long, help: ArgumentHelp("The point to mark: on the node from its top-left, or on the page.", valueName: "x,y"))
    var at: CommentPoint?

    @Flag(name: .long, help: "Comment on the empty canvas: --at is a page point, and no node is given.")
    var canvas: Bool = false

    @Option(name: .customLong("id"), help: ArgumentHelp("The id to give the message; one is minted otherwise.", valueName: "id"))
    var messageID: String?

    @Option(
        name: .customShort("F"),
        help: ArgumentHelp("The text, from a file. `-` reads standard input.", valueName: "file")
    )
    var textFile: String?

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Author>
    @OptionGroup var output: OutputOptions

    /// Starts the thread and prints its id.
    func run() async throws {
        let url = try file.existingFile()
        let (node, inline) = try target()
        let text = try CommentWrite.text(inline, file: textFile)
        let author = try CommentWrite.author(identity.identity)
        let point = try point(on: node, inline: inline)
        let id = messageID
        let date = Date()

        try await CommentWrite.run(
            self, file: url, identity: author, action: .thread, effect: preview.effect, json: output.json
        ) { document in
            let anchor = try node.map { try PenComment.anchor(on: $0, x: point.x, y: point.y, in: document) }
                ?? PenCommentThread.Anchor(node: nil, x: point.x, y: point.y)
            let write = try PenComment.startThread(text, anchor: anchor, author: author, at: date, id: id, in: document)
            return CommentWrite.Built(write: write, thread: write.threadID, createdAt: PenComment.createdAt(date))
        }
    }

    /// The node and the inline text the positional words give.
    private func target() throws -> (node: String?, text: String?) {
        let (node, text): (String?, String?) = switch words.count {
        case 0: (nil, nil)
        case 1: textFile == nil ? (nil, words[0]) : (words[0], nil)
        case 2: (words[0], words[1])
        default:
            throw CommandFailure(
                message: "comment takes a node and one text argument; got \(words.count) words. "
                    + "Quote the text: woodcase comment <file> <node> \"…\".",
                exitCode: .usage
            )
        }
        if canvas, let node {
            throw CommandFailure(
                message: "--canvas puts the comment on the page, so it takes no node: drop `\(node)`, "
                    + "or drop --canvas to comment on it.",
                exitCode: .usage
            )
        }
        return (node, text)
    }

    /// The point to mark: `--at`, else a node's top-left; a canvas comment must say where.
    private func point(on node: String?, inline: String?) throws -> CommentPoint {
        if let at { return at }
        if node != nil { return CommentPoint(x: 0, y: 0) }
        let mistaken = inline.map { " To comment on `\($0)`, put the text after it: woodcase comment <file> \($0) \"…\"." }
        throw CommandFailure(
            message: "With no node the comment is on the page, and needs --at x,y in page coordinates."
                + (mistaken ?? ""),
            exitCode: .usage
        )
    }
}
