//
//  CopyCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Duplicates a subtree with fresh ids, or instantiates a component.
///
/// The verb is an adapter: it types the argv values, decides how many copies were
/// asked for, and hands one ``BatchOperation/CopyOp`` to
/// ``Woodcase/BatchApplier/applyOne(_:to:recorder:log:file:)``. Every decision about
/// *where a key lands* belongs to ``Woodcase/CopyAssignment``, which the batch `cp`
/// op splits its keys through as well — so `woodcase cp` and `{"op":"cp"}` cannot mean
/// different things by `Header/Title/kind.content`.
struct CopyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "cp",
        abstract: "Write: copy a node into a parent, applying properties to the copy.",
        discussion: """
        An act verb. Copying a reusable component makes an instance of it — a ref — \
        which is what Pen does when you place a component; copying anything else \
        deep-copies it with fresh ids. The name → id tree printed back is the only \
        place those ids appear.

        Properties are applied to the copy, never to the source. A key with no \
        slashes lands on the copy's root; a key written as a name path \
        (Header/Title/kind.content) lands on that node *inside the copy*, resolved \
        against the copy by id, so the original is never touched. If any of them \
        cannot be applied, the whole copy is abandoned and the file is unchanged.

        When the copy is an instance, a nested key becomes one of its overrides in \
        the same write — kind.content is stored as content, the raw .pen name the \
        `descendants` map is keyed in — so placing a component and titling it is one \
        command and one vocabulary. A raw name is taken as written, either way.

        A key may also be a name the source PUBLISHES: a component declares its \
        parameters in common.metadata._props as name → the name path of the node the \
        value belongs to, so `label=Hi` means the same as Body/Title/kind.content=Hi. \
        `woodcase get <component>` lists them, and a row of an --each file may be \
        keyed by them too.

        \(PropertyAssignment.valueRules)

        A root-level copy (parent `document`) is placed in empty space to the right \
        of the existing roots: the source's own x and y say where the source sits, \
        not where its copy belongs. Pass common.x or common.y to put it somewhere \
        in particular.

        --times N makes N copies, in order, in one write. Because identical names \
        break path addressing, --times requires common.name to contain the \
        \(CopyCommand.timesPlaceholder) placeholder — replaced with 1, 2, … N in \
        every property that carries it, not only common.name.

        --each rows.jsonl makes one copy per row, so each copy can carry its own \
        content. A row is one JSON object whose keys are exactly the keys above — \
        common.name, Chip/kind.fills, Name/kind.content — laid over any key given on \
        the command line, which is how a shared value is written once. \
        \(CopyCommand.timesPlaceholder) is the 1-based row number. A row key that \
        names no node inside the source refuses the whole run, naming the row, before \
        anything is written. --each and --times are alternatives; pass one.

        --rev, when given, guards only the first copy; the rest apply against the \
        document the previous copy just produced.

        \(AddressArgument.addressForms)

        EXAMPLE
          woodcase cp design.pen Home document common.name=Checkout \\
            Header/Title/kind.content=Checkout --as ana
          woodcase cp design.pen Row Cards common.name='Card \(CopyCommand.timesPlaceholder)' --times 3
          woodcase cp design.pen Chip Row --each rows.jsonl
            where rows.jsonl is
              {"common.name":"Chip 1","Label/kind.content":"Draft"}
              {"common.name":"Chip 2","Label/kind.content":"Shipped"}
        """
    )

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "The node to copy.")
    var node: String

    @Argument(help: "The parent to copy into, or `document` for the document root.")
    var parent: String

    @Argument(help: "Properties for the copy, as key=value or path/key=value.")
    var assignments: [String] = []

    @Option(
        name: .customShort("F"),
        help: ArgumentHelp("A JSON object of properties. `-` reads standard input.", valueName: "file")
    )
    var propertiesFile: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            """
            Copy N times in order, instead of once. Requires common.name to contain \
            \(CopyCommand.timesPlaceholder) (1-based).
            """,
            valueName: "N"
        )
    )
    var times: Int?

    @Option(
        name: .long,
        help: ArgumentHelp(
            """
            One copy per row of a JSONL file, each row a JSON object of the same \
            key=value properties this verb takes. `-` reads standard input. Not with \
            --times.
            """,
            valueName: "rows.jsonl"
        )
    )
    var each: String?

    @OptionGroup var position: PositionOption
    @OptionGroup var revision: RevisionOption
    @OptionGroup var premise: GuardOption
    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// The 1-based placeholder `--times` requires in `common.name`.
    ///
    /// Identical copies would be indistinguishable by name path, so `--times`
    /// refuses without it rather than auto-suffixing a name the caller did not ask for.
    static let timesPlaceholder = CopyAssignment.rowPlaceholder

    func run() async throws {
        let url = try file.existingFile()
        let source = try AddressArgument.node(node)
        let parentAddress = try AddressArgument.parent(parent)
        let properties = try PropertyAssignment.properties(from: assignments, file: propertiesFile)
        let rows = try Self.rows(times: times, each: each, properties: properties)
        let index = position.at
        let expected = revision.rev
        let pins = try premise.guards()
        let effect = preview.effect
        let writer = identity.identity
        let wantsJSON = output.json

        try await runReportingFailures(editing: url) {
            let outcome = try await PenFileTransaction.run(at: url, identity: writer, effect: effect, fonts: .shared) { document, recorder in
                let overlapping = RootOverlapWarnings.baseline(in: document)
                do {
                    let findings = try effect.preview(of: document)
                    let copy = try BatchApplier.applyOne(
                        .cp(BatchOperation.CopyOp(
                            source: source, parent: parentAddress, at: index,
                            props: properties.isEmpty ? nil : properties,
                            each: rows, rev: expected, guards: pins
                        )),
                        to: document,
                        recorder: recorder,
                        log: ActivityLogLocation.log(for: url),
                        file: url
                    )
                    let warnings = RootOverlapWarnings.lines(
                        since: overlapping, in: document, file: url.path
                    )
                    return try WrittenOutcome(
                        rendered: WriteReport(
                            created: copy.created,
                            path: copy.path,
                            id: copy.id,
                            nodeRevision: copy.id.flatMap { document.revision(of: $0) },
                            documentRevision: document.documentRevision,
                            warnings: warnings,
                            node: copy.node,
                            divergences: copy.divergences,
                            dryRun: effect == .dryRun,
                            lint: findings?.introduced(in: document) ?? []
                        ).rendered(json: wantsJSON),
                        warnings: warnings
                    )
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
            }
            OutsideWriteNote.report(outcome, json: wantsJSON)
            print(outcome.value.rendered)
            RootOverlapWarnings.report(outcome.value.warnings)
        }
    }

    // MARK: - How many copies

    /// The rows this invocation copies with, or `nil` for a single copy.
    ///
    /// `--times N` and `--each rows.jsonl` are the same mechanism seen from two sides:
    /// N copies that differ only by their number, and N copies that differ by whatever
    /// the rows say. So `--times` is N empty rows, and everything below the verb —
    /// substitution, placement, the all-or-nothing pre-flight — has one path to
    /// maintain.
    ///
    /// - Parameters:
    ///   - times: The raw `--times` value, or `nil`.
    ///   - each: The `--each` path, or `nil`.
    ///   - properties: The properties given on argv, for the `--times` placeholder check.
    /// - Returns: One property map per copy, or `nil` when neither flag was given.
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` when both flags are given,
    ///   when `--times` is not a sensible count or lacks the placeholder, or when the
    ///   rows file cannot be read or decoded.
    static func rows(
        times: Int?,
        each: String?,
        properties: [String: AnyCodable]
    ) throws -> [[String: AnyCodable]]? {
        guard times == nil || each == nil else {
            throw CommandFailure(
                message: "--each and --times both say how many copies to make; pass one. "
                    + "Use --times N to repeat a copy that differs only by its "
                    + "\(timesPlaceholder), and --each rows.jsonl when each copy carries "
                    + "its own content.",
                exitCode: .usage
            )
        }
        if let each {
            return try rows(fromFile: each)
        }
        guard let times else { return nil }
        guard times >= 1 else {
            throw CommandFailure(
                message: "--times must be at least 1, not \(times).",
                exitCode: .usage
            )
        }
        try requirePlaceholder(in: properties)
        return Array(repeating: [:], count: times)
    }

    /// Reads a `--each` file: one JSON object of properties per line.
    private static func rows(fromFile path: String) throws -> [[String: AnyCodable]] {
        let text = try String(decoding: InputFile.data(at: path), as: UTF8.self)
        do {
            return try CopyAssignment.decodeRows(text)
        } catch {
            throw CommandFailure.describing(error)
        }
    }

    /// Refuses `--times` unless `common.name` carries the placeholder.
    ///
    /// - Parameter properties: The properties given on argv.
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` naming the placeholder and
    ///   showing a worked example, when `common.name` is missing, is not a string, or
    ///   does not contain it.
    private static func requirePlaceholder(in properties: [String: AnyCodable]) throws {
        guard case let .string(name)? = properties["common.name"], name.contains(timesPlaceholder)
        else {
            throw CommandFailure(
                message: "cp --times requires common.name to contain the \(timesPlaceholder) "
                    + "placeholder (1-based), so each copy gets a distinct, addressable name — "
                    + "for example common.name='Bar \(timesPlaceholder)'. To vary more than the "
                    + "number, give each copy a row with --each rows.jsonl.",
                exitCode: .usage
            )
        }
    }
}
