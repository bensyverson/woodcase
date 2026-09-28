//
//  ImportsRemoveCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase imports rm <file> <alias>` — drop an import, unless something needs it.
///
/// ```bash
/// woodcase imports rm design.pen V
/// # Cannot remove V: 2 nodes reference it — Canvas/Button, Canvas/Title.
/// # Pass --force to remove it anyway, leaving those references unresolved.
/// ```
///
/// Removal is the one import operation the batch grammar deliberately does not carry,
/// for the reason it carries no variable removal: its consequence can exceed its
/// target. A `ref` whose target is `V:Bt0aA` does not fail when the `V` import goes —
/// it resolves to nothing. So the refusal is ``Woodcase/NameInUse``, the same library
/// answer `vars rm` refuses on, and `--force` is how it is opted into.
struct ImportsRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Write: drop a library import, refusing while anything still uses it.",
        discussion: """
        A write verb whose consequence can exceed its target: a ref whose target is \
        V:Bt0aA does not fail when the V import goes, it resolves to nothing. So \
        removal is refused while any node reaches into the alias's namespace, listing \
        what would be affected, and --force is how that is opted into. Rehearse the \
        forced removal first: --force --dry-run prints the findings the stranded \
        references would raise, and removes nothing.

          woodcase imports rm design.pen V --as ana
          woodcase imports rm design.pen V --force --dry-run
        """
    )

    /// What one `rm` did.
    struct Report: Friendly {
        /// Creates a report.
        ///
        /// - Parameters:
        ///   - alias: The alias removed.
        ///   - path: The path it resolved to.
        ///   - revision: The document revision the write left behind.
        ///   - dryRun: Whether this was a rehearsal. A rehearsal drops the revision —
        ///     the file is still at the one it had — and gains the marker and the
        ///     findings. See ``DryRunOption``.
        ///   - lint: The findings the removal would introduce, from
        ///     ``Woodcase/LintPreview``. Only a dry run has any, and a forced removal is
        ///     where they matter: every reference left behind is one of them.
        init(
            alias: String,
            path: String,
            revision: String,
            dryRun: Bool = false,
            lint: [LintFinding] = []
        ) {
            self.alias = alias
            self.path = path
            self.revision = dryRun ? nil : revision
            self.dryRun = dryRun ? true : nil
            self.lint = dryRun ? lint : nil
        }

        /// The alias removed.
        let alias: String

        /// The path it resolved to.
        let path: String

        /// The document revision the write left behind, or `nil` for a dry run — which
        /// made none, and leaves the file at the one it already had.
        let revision: String?

        /// `true` when nothing was written, `nil` when something was.
        let dryRun: Bool?

        /// The lint findings the removal would introduce, or `nil` for a real write.
        let lint: [LintFinding]?

        /// The rows a removal answers with: what went, then the revision.
        ///
        /// A dry run leads with ``DryRunOption/marker``, prints no revision — it made
        /// none — and follows with the findings it would introduce.
        var text: String {
            var lines: [String] = dryRun == true ? [DryRunOption.marker] : []
            lines.append("Removed \(alias) (\(path)).")
            if let revision {
                lines.append("revision \(revision)")
            }
            if let lint, !lint.isEmpty {
                lines.append(LintFormatter.text(lint))
            }
            return lines.joined(separator: "\n")
        }
    }

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "The import alias to remove.")
    var alias: String

    @Flag(
        name: .long,
        help: "Remove it even though nodes still reach into its namespace."
    )
    var force: Bool = false

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Removes the import, or refuses and says what would have been affected.
    func run() async throws {
        let url = try file.existingFile()
        let alias = alias
        let force = force
        let effect = preview.effect
        try await runReportingFailures(editing: url) {
            let outcome = try await PenFileTransaction.run(
                at: url, identity: identity.identity, effect: effect,
                fonts: .shared
            ) {
                document, recorder in
                do {
                    return try Self.remove(
                        alias, force: force, from: document, named: url.lastPathComponent,
                        through: recorder, effect: effect
                    )
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
            }
            let report = outcome.value
            OutsideWriteNote.report(outcome, json: output.json)
            if output.json {
                try print(ImportFormatter.json(report))
            } else {
                print(report.text)
            }
        }
    }

    // MARK: - Private

    /// Checks the consequence, then removes.
    ///
    /// - Parameters:
    ///   - alias: The import alias to remove.
    ///   - force: Whether to remove it despite the references it would strand.
    ///   - document: The document being edited.
    ///   - fileName: The file's name, for the message when the alias is not there.
    ///   - recorder: The recorder the removal goes through.
    ///   - effect: Whether this is a rehearsal, which is what decides whether the
    ///     findings are collected and the revision dropped.
    /// - Returns: What was removed.
    /// - Throws: ``CommandFailure`` when no such import exists, or when something
    ///   reaches into the namespace and `force` is `false`.
    private static func remove(
        _ alias: String,
        force: Bool,
        from document: EditableDocument,
        named fileName: String,
        through recorder: ActivityRecorder,
        effect: WriteEffect
    ) throws -> Report {
        let findings = try effect.preview(of: document)
        guard let path = document.imports?[alias] else {
            throw CommandFailure(
                message: """
                No import aliased \(alias) in \(fileName). \
                `woodcase imports \(fileName)` lists the ones there are.
                """,
                exitCode: .usage
            )
        }
        let inUse = NameInUse.importAlias(alias, in: document)
        if !force, !inUse.isEmpty {
            throw CommandFailure(
                message: inUse.sentence(in: .command(file: fileName)),
                exitCode: .usage
            )
        }
        try recorder.apply(.removeImport(EditOperation.RemoveImport(alias: alias)))
        return try Report(
            alias: alias,
            path: path,
            revision: document.documentRevision,
            dryRun: effect == .dryRun,
            lint: findings?.introduced(in: document) ?? []
        )
    }
}
