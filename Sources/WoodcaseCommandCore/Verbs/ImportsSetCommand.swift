//
//  ImportsSetCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase imports set <file> <alias> <path>` — add an import or repoint one.
///
/// ```bash
/// woodcase imports set design.pen V ./library.pen
/// woodcase imports set design.pen V ./library-v2.pen
/// ```
///
/// An alias the document already has has its path changed; one it does not have is
/// added — the same add-or-change `vars set` makes, and the same one the batch line
/// `{"op":"import","alias":…,"path":…}` makes.
///
/// Repointing an alias is the one write here whose consequence can exceed its target,
/// and it is not refused: every `V:`-prefixed identifier now resolves against a
/// different file, so a component the old library defined and the new one does not
/// stops resolving. `--dry-run` rehearses it and prints the findings that would follow.
struct ImportsSet: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set",
        abstract: "Write: add a library import, or change the path an alias points at.",
        discussion: """
        The alias is the prefix every identifier the library defines takes — a component \
        `Bt0aA` in the library imported as V is addressed `V:Bt0aA` — so changing an \
        alias's path repoints every one of them at once. Rehearse it with --dry-run, \
        which prints the findings the change would introduce and writes nothing.

          woodcase imports set design.pen V ./library.pen --as ana
        """
    )

    /// What one `set` did.
    struct Report: Friendly {
        /// Creates a report.
        ///
        /// - Parameters:
        ///   - importRow: The import as it now stands.
        ///   - revision: The document revision the write left behind.
        ///   - dryRun: Whether this was a rehearsal. A rehearsal drops the revision —
        ///     the file is still at the one it had — and gains the marker and the
        ///     findings. See ``DryRunOption``.
        ///   - lint: The findings the write would introduce, from
        ///     ``Woodcase/LintPreview``. Only a dry run has any.
        init(
            importRow: ImportFormatter.Row,
            revision: String,
            dryRun: Bool = false,
            lint: [LintFinding] = []
        ) {
            self.importRow = importRow
            self.revision = dryRun ? nil : revision
            self.dryRun = dryRun ? true : nil
            self.lint = dryRun ? lint : nil
        }

        /// The import as it now stands.
        let importRow: ImportFormatter.Row

        /// The document revision the write left behind, or `nil` for a dry run — which
        /// made none, and leaves the file at the one it already had.
        let revision: String?

        /// `true` when nothing was written, `nil` when something was.
        let dryRun: Bool?

        /// The lint findings the write would introduce, or `nil` for a real write.
        let lint: [LintFinding]?

        /// The rows a `set` answers with: the import, then the revision.
        ///
        /// A dry run leads with ``DryRunOption/marker``, prints no revision — it made
        /// none — and follows with the findings it would introduce.
        var text: String {
            var lines: [String] = dryRun == true ? [DryRunOption.marker] : []
            lines += ImportFormatter.lines(for: [importRow])
            if let revision {
                lines.append("revision \(revision)")
            }
            if let lint, !lint.isEmpty {
                lines.append(LintFormatter.text(lint))
            }
            return lines.joined(separator: "\n")
        }

        /// `import` on the wire: the Swift name only avoids the keyword.
        private enum CodingKeys: String, CodingKey {
            case importRow = "import"
            case revision, dryRun, lint
        }
    }

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "The alias every identifier the library defines is prefixed with.")
    var alias: String

    @Argument(help: "The file path or URL the alias resolves to.")
    var path: String

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Writes the import and prints what it made.
    func run() async throws {
        let url = try file.existingFile()
        let alias = alias
        let path = path
        let effect = preview.effect
        try await runReportingFailures(editing: url) {
            let outcome = try await PenFileTransaction.run(
                at: url, identity: identity.identity, effect: effect,
                fonts: .shared
            ) {
                document, recorder in
                do {
                    return try Self.apply(
                        alias: alias, path: path, to: document, through: recorder, effect: effect
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

    /// Adds the import, or changes the path of the alias the document already has.
    ///
    /// - Parameters:
    ///   - alias: The namespace prefix.
    ///   - path: The file path or URL it resolves to.
    ///   - document: The document being edited.
    ///   - recorder: The recorder the write goes through, so the activity log gets an
    ///     `import` event.
    ///   - effect: Whether this is a rehearsal, which is what decides whether the
    ///     findings are collected and the revision dropped.
    /// - Returns: What the write made.
    /// - Throws: Whatever the operation itself throws.
    private static func apply(
        alias: String,
        path: String,
        to document: EditableDocument,
        through recorder: ActivityRecorder,
        effect: WriteEffect
    ) throws -> Report {
        let findings = try effect.preview(of: document)
        if document.imports?[alias] == nil {
            try recorder.apply(.addImport(EditOperation.AddImport(alias: alias, path: path)))
        } else {
            try recorder.apply(.updateImport(EditOperation.UpdateImport(alias: alias, path: path)))
        }
        return try Report(
            importRow: ImportFormatter.row(for: alias, path: path, in: document),
            revision: document.documentRevision,
            dryRun: effect == .dryRun,
            lint: findings?.introduced(in: document) ?? []
        )
    }
}
