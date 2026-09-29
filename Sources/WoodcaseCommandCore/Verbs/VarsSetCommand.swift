//
//  VarsSetCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase vars set <file> name=value …` — add variables or change them.
///
/// ```bash
/// woodcase vars set design.pen brand=#FF6600
/// woodcase vars set design.pen brand=#221100 --theme mode=dark
/// woodcase vars set design.pen bg=#111 fg=#eee --theme mode=dark
/// woodcase vars set design.pen label=16 --type string
/// woodcase vars set design.pen -- --accent=#e0561a
/// ```
///
/// The type is settled before the value is: `--type` if given, else the type the
/// variable already declares, else what the literal reads as
/// (``VariableTyping/inferredType(of:)``). A variable's declared type therefore never
/// changes because a later value looked like something else — which is what keeps the
/// nodes bound to it resolving.
///
/// `--theme` pins the value to one or more axis options, and registers what it names:
/// an axis the document does not have is created with that one option, and an option
/// an axis does not have is appended. That is how Pen itself grows a theme, and it
/// means a themed value never has to be preceded by a separate `vars axis add`.
///
/// Several `name=value` pairs go through **one** transaction, with `--theme` and
/// `--type` applying to every one of them, so a token layer is one call rather than one
/// process launch per color. Each variable is still its own `var` event in the
/// activity log, sharing the call's batch id, so `activity` reads as it always did and
/// one `undo` takes the whole call back.
///
/// A name the document already defines is announced before the outline — its old value,
/// every themed option of it, and how many things were resolving through it — because
/// `set` is add-or-change and the outline alone cannot tell the two apart. See
/// ``displaced(_:)``.
struct VarsSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Write: add variables or change them, optionally for one theme.",
        discussion: """
        The value is typed by --type, else by the variable's existing type, else by \
        what it looks like: #RGB/#RRGGBB/#RRGGBBAA is a color, true/false a boolean, \
        a number a number, anything else a string. A value beginning with $ is a \
        reference to another variable.

        --theme registers what it names: an axis the document lacks is created with \
        that one option, and an option an axis lacks is appended, so a themed value \
        never needs a `vars axis add` first.

          woodcase vars set design.pen brand=#0055ff --theme mode=dark --as ana

        Several name=value pairs go through one transaction, and --theme and --type \
        apply to every pair.

          woodcase vars set design.pen bg=#111111 fg=#eeeeee --theme mode=dark --as ana

        \(SeparatorRemedy.rule)

          \(SeparatorRemedy.example)

        A name the document already defines is announced first, with its old value and \
        its reference count, because `set` adds or changes and the outline alone cannot \
        tell you which it did.
        """
    )

    /// What one `set` did.
    struct Report: Friendly {
        /// Creates a report.
        ///
        /// - Parameters:
        ///   - variables: The variables as they now stand, one per pair given, in the
        ///     order they were given.
        ///   - previous: The rows of those that already existed, read before the write.
        ///     Dropped when every name was fresh — there is nothing to compare.
        ///   - axes: The theme axes this write created or added an option to.
        ///   - revision: The document revision the write left behind.
        ///   - dryRun: Whether this was a rehearsal. A rehearsal drops the revision —
        ///     the file is still at the one it had — and gains the marker and the
        ///     findings. See ``DryRunOption``.
        ///   - lint: The findings the write would introduce, from
        ///     ``Woodcase/LintPreview``. Only a dry run has any.
        init(
            variables: [VariableFormatter.Row],
            previous: [VariableFormatter.Row],
            axes: [VariableFormatter.Axis],
            revision: String,
            dryRun: Bool = false,
            lint: [LintFinding] = []
        ) {
            self.variables = variables
            self.previous = previous.isEmpty ? nil : previous
            self.axes = axes
            self.revision = dryRun ? nil : revision
            self.dryRun = dryRun ? true : nil
            self.lint = dryRun ? lint : nil
        }

        /// The variables as they now stand, with every variant each holds.
        let variables: [VariableFormatter.Row]

        /// The rows, as they stood *before* this write, of the names that already
        /// existed — or `nil` when every name in the call was fresh.
        ///
        /// A field rather than a sentence, so a caller reading `--json` branches on the
        /// reference count rather than parsing the line the text form prints.
        let previous: [VariableFormatter.Row]?

        /// The theme axes this write created or added an option to.
        let axes: [VariableFormatter.Axis]

        /// The document revision the write left behind, or `nil` for a dry run — which
        /// made none, and leaves the file at the one it already had.
        let revision: String?

        /// `true` when nothing was written, `nil` when something was.
        let dryRun: Bool?

        /// The lint findings the write would introduce, or `nil` for a real write.
        let lint: [LintFinding]?
    }

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(
        help: ArgumentHelp(
            "The variables and their values; give several to write them in one transaction.",
            valueName: "name=value"
        )
    )
    var assignments: [VariableAssignment]

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Pin every pair's value to theme options, registering any the document lacks.",
            valueName: "axis=option,…"
        )
    )
    var theme: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Declare every pair's type instead of taking it from the value.",
            valueName: "type"
        )
    )
    var type: PenVariableType?

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Applies the assignments and prints what they made.
    func run() async throws {
        let url = try file.existingFile()
        let assignments = assignments
        let declared = type
        let effect = preview.effect
        try await runReportingFailures(editing: url) {
            let pin = try ThemePinParser.parse(theme)
            let outcome = try await PenFileTransaction.run(
                at: url, identity: identity.identity, effect: effect,
                fonts: .shared
            ) {
                document, recorder in
                do {
                    return try Self.apply(
                        assignments, declaredType: declared, pinnedTo: pin,
                        to: document, through: recorder, effect: effect
                    )
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
            }
            let report = outcome.value
            OutsideWriteNote.report(outcome, json: output.json)
            if output.json {
                try print(VariableFormatter.json(report))
            } else {
                print(Self.text(report))
            }
        }
    }

    // MARK: - Private

    /// The rows a `set` answers with: what it displaced, the variables, any axis it
    /// grew, the revision.
    ///
    /// A dry run leads with ``DryRunOption/marker``, prints no revision — it made none —
    /// and follows with the findings it would introduce, in `lint`'s own line format.
    private static func text(_ report: Report) -> String {
        var lines: [String] = report.dryRun == true ? [DryRunOption.marker] : []
        lines += (report.previous ?? []).map(displaced)
        lines += VariableFormatter.lines(for: report.variables)
        lines += report.axes.map { "axis \($0.name): \($0.options.joined(separator: ", "))" }
        if let revision = report.revision {
            lines.append("revision \(revision)")
        }
        if let lint = report.lint, !lint.isEmpty {
            lines.append(LintFormatter.text(lint))
        }
        return lines.joined(separator: "\n")
    }

    /// The one line a name that already existed earns, before the outline.
    ///
    /// The outline `set` prints is the same whether the name was new or not, so a
    /// caller told to "add `--warn`" could recolor nine live references and read a
    /// clean success. This says what was there: the type, every option's value for a
    /// themed variable — all of them, because the caller is about to replace one and
    /// keep the rest — and how many things were resolving through it.
    ///
    /// - Parameter row: The variable as it stood before the write.
    /// - Returns: One line for standard output.
    private static func displaced(_ row: VariableFormatter.Row) -> String {
        let plain = row.values.count == 1 && row.values.first?.theme == nil
        let values = row.values.map { variant in
            plain
                ? VariableFormatter.display(variant.value)
                : "\(VariableFormatter.pin(row: variant.theme)) \(VariableFormatter.display(variant.value))"
        }.joined(separator: ", ")
        let count = row.references.nodes + row.references.variables
        let consequence = switch count {
        case 0: "."
        case 1: " — this write changes what it resolves to."
        default: " — this write changes what all \(count) of them resolve to."
        }
        return "\(row.name) already existed with \(VariableFormatter.text(for: row.references)), "
            + "as \(row.type.rawValue) \(values)\(consequence)"
    }
}
