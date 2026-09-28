//
//  FindCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase
import WoodcaseScripting

/// Prints the rows of a settled tree read that a JavaScript predicate keeps.
///
/// `tree` with a question attached. The rows are the rows `tree` builds and the bytes
/// are the bytes `tree` prints, so anything that reads one reads the other; the only
/// thing `find` adds is which rows appear and an exit code a shell can branch on.
struct Find: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "find",
        abstract: "Read: the rows of the settled tree that answer a JavaScript predicate.",
        discussion: """
        A read verb: it takes a shared lock, writes nothing, and leaves the file's \
        bytes and modification date alone.

        The predicate is a JavaScript arrow function taking one row — the same row \
        `tree --json` prints — and answering truthy for the ones to keep. There is no \
        grammar to learn beyond JavaScript, and no `doc`: a predicate reads one row at \
        a time and cannot write. `woodcase js` is where a program with `doc` lives.

          woodcase find design.pen 'r => r.type === "text" && r.rect.height < 2'
          woodcase find design.pen Dashboard 'r => r.clip !== "none"'
          woodcase find design.pen 'r => r.props["kind.fontSize"] < 12' --props kind.fontSize

        A ROW carries type, name, address, id, rev, depth, rect, absRect, clip, \
        overflowAxes, isReusable, isInstance, isSlot, childCount — and the columns \
        --props asked for, read as `r.props["kind.fontSize"]`. A member a row does not \
        have is refused rather than read as `undefined`, because `undefined < 12` is \
        `false` and a query that answers a question nobody asked is worse than one that \
        stops.

        OUTPUT is `tree`'s, filtered: the same header, the same columns, the same \
        --json report, so `find` pipes wherever `tree` does. Matches exit 0; no matches \
        exit 1 and print nothing, so `woodcase find … && …` branches on the answer. A \
        predicate that will not parse, or throws, exits 2 naming the row it threw on.

        -F reads the predicate from a file, or from standard input with `-F -`, for a \
        question that outgrows a line.
        """
    )

    @Argument(help: "The .pen file to read.")
    var file: PenFilePath

    @Argument(help: "The subtree to search — an id, a name path, or an instance path. Omit for the whole file.")
    var node: String?

    @Argument(help: "The predicate: a JavaScript arrow function of one row, e.g. 'r => r.type === \"text\"'.")
    var predicate: String?

    @Option(
        name: .customShort("F"),
        help: ArgumentHelp(
            "The predicate, when it outgrew a line. `-` reads standard input.",
            valueName: "file"
        )
    )
    var predicateFile: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Property paths to show as columns and expose as r.props[…], comma separated. "
                + "Bare --props shows \(Tree.defaultPropertyPaths.joined(separator: ", "))."
        )
    )
    var props: String?

    @Flag(name: .long, help: "Walk into component instances, addressing their nodes by id path.")
    var expand: Bool = false

    @Flag(name: .long, help: "Print rects in document space rather than relative to each node's parent.")
    var absolute: Bool = false

    @OptionGroup var output: OutputOptions

    /// Reads the file, filters its rows, and prints what is left.
    func run() async throws {
        let url = try file.existingFile()
        let properties = Tree.propertyPaths(in: props)
        let source = try predicateSource()

        try await runReportingFailures(editing: url) {
            let diagnostics = PenDiagnosticCollector()
            defer { StandardError.write(diagnostics) }
            try await PenFileTransaction.read(at: url, diagnostics: diagnostics, fonts: .shared) { document in
                let rows: [TreeRow]
                do {
                    rows = try TreeView.rows(
                        of: document,
                        root: subtree,
                        expandInstances: expand,
                        properties: properties
                    )
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
                PropertyColumnWarning.warnAboutEmptyColumns(properties, in: rows, expand: expand)

                let outcome = RowPredicate.match(rows, where: source, properties: properties)
                if let error = outcome.error {
                    throw CommandFailure(
                        message: PredicateFailureMessage.describe(error, row: outcome.failingRow),
                        exitCode: .usage
                    )
                }
                // A clean negative prints nothing at all, in either form: the exit code
                // is the whole answer, and an empty listing in a pipe reads as a match.
                guard !outcome.rows.isEmpty else { throw ExitCode.cleanNegative }
                let text = try render(
                    outcome.rows,
                    revision: document.documentRevision,
                    properties: properties
                )
                print(text)
            }
        }
    }

    // MARK: - The predicate

    /// The subtree to search, or `nil` for the whole file.
    ///
    /// `nil` when the one operand written was the predicate — see ``predicateSource()``
    /// for why a lone operand is read that way.
    private var subtree: String? {
        predicate == nil && predicateFile == nil ? nil : node
    }

    /// Where the predicate comes from: the positional argument, or `-F`.
    ///
    /// The two positional operands are the subtree and the predicate, and a caller who
    /// gives one has given the predicate — `find <file> <predicate>` is the everyday
    /// form. So a lone operand shifts into the predicate's place unless `-F` has already
    /// filled it, in which case the operand is the subtree it was always going to be.
    ///
    /// - Returns: The predicate, named for the report a failure lands in.
    /// - Throws: ``CommandFailure`` when the predicate is missing or given twice.
    private func predicateSource() throws -> ScriptSource {
        if let path = predicateFile {
            guard predicate == nil else {
                throw CommandFailure(
                    message: "The predicate was given twice: once as an argument and once with -F "
                        + "\(path). Keep one — -F is for the question that outgrew a line.",
                    exitCode: .usage
                )
            }
            let data = try InputFile.data(at: path)
            return .text(String(decoding: data, as: UTF8.self), name: path)
        }
        guard let written = predicate ?? node else {
            throw CommandFailure(
                message: "find needs a predicate: a JavaScript arrow function of one row, like "
                    + "'r => r.type === \"text\"'. `woodcase tree \(file.path)` is the same "
                    + "listing with nothing filtered out.",
                exitCode: .usage
            )
        }
        return .text(written, name: "<argv>")
    }

    // MARK: - Output

    /// The bytes the verb prints: the JSON report, or the header line and the outline.
    ///
    /// Byte for byte what `tree` prints for the same rows, header included — the header
    /// carries the revision to quote back on the write that follows, which is the whole
    /// reason a query runs before an edit.
    ///
    /// - Parameters:
    ///   - rows: The rows the predicate kept.
    ///   - revision: The document's revision, for the header or the report.
    ///   - properties: The property columns that were asked for.
    /// - Returns: The whole of stdout, without a trailing newline.
    /// - Throws: Whatever the JSON encoder throws.
    private func render(_ rows: [TreeRow], revision: String, properties: [String]) throws -> String {
        guard !output.json else {
            return try TreeFormatter.json(rows, revision: revision)
        }
        let header = "rev \(revision)  \(rows.count) \(rows.count == 1 ? "row" : "rows")"
            + (absolute ? "  absolute" : "")
        return "\(header)\n\(TreeFormatter.text(rows, properties: properties, absolute: absolute))"
    }
}
