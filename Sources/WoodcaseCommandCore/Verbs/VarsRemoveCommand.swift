//
//  VarsRemoveCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase vars rm <file> <name>` — remove a variable, unless something needs it.
///
/// ```bash
/// woodcase vars rm design.pen brand
/// # Cannot remove brand: 3 nodes reference it — Card/Title, Card/Body, Nav/Logo.
/// # Pass --force to remove it anyway, leaving those references unresolved.
/// ```
///
/// Removal is the one variable operation the batch grammar deliberately does not
/// carry, because its consequence can exceed its target: a node whose fill is
/// `$brand` does not fail when `brand` disappears, it silently renders the unresolved
/// reference. So the refusal, and the `--force` that overrides it, live here — over
/// ``EditableDocument/references(to:)``, which is the library's fact about who would
/// be affected.
struct VarsRemove: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Write: remove a variable, refusing while anything still references it.",
        discussion: """
        A write verb whose consequence can exceed its target: a node whose fill is \
        $brand does not fail when brand disappears, it silently renders the \
        unresolved reference. So removal is refused while anything references the \
        variable, listing what would be affected, and --force is how that is opted \
        into. Rehearse the forced removal first: --force --dry-run prints an \
        unresolved-variable finding for every node that would be left holding the \
        name, and removes nothing.

          woodcase vars rm design.pen brand --as ana
          woodcase vars rm design.pen brand --force --dry-run
        """
    )

    /// What one `rm` did.
    struct Report: Friendly {
        /// Creates a report.
        ///
        /// - Parameters:
        ///   - name: The variable removed.
        ///   - type: The type it declared.
        ///   - revision: The document revision the write left behind.
        ///   - dryRun: Whether this was a rehearsal. A rehearsal drops the revision —
        ///     the file is still at the one it had — and gains the marker and the
        ///     findings. See ``DryRunOption``.
        ///   - lint: The findings the removal would introduce, from
        ///     ``Woodcase/LintPreview``. Only a dry run has any, and a forced removal is
        ///     where they matter: every reference left behind is one of them.
        init(
            name: String,
            type: PenVariableType,
            revision: String,
            dryRun: Bool = false,
            lint: [LintFinding] = []
        ) {
            self.name = name
            self.type = type
            self.revision = dryRun ? nil : revision
            self.dryRun = dryRun ? true : nil
            self.lint = dryRun ? lint : nil
        }

        /// The variable removed.
        let name: String

        /// The type it declared.
        let type: PenVariableType

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
            lines.append("Removed \(name) (\(type.rawValue)).")
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

    @Argument(help: "The variable to remove, without the $.")
    var name: String

    @Flag(
        name: .long,
        help: "Remove it even though nodes or other variables still reference it."
    )
    var force: Bool = false

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Removes the variable, or refuses and says what would have been affected.
    func run() async throws {
        let url = try file.existingFile()
        let name = name
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
                        name, force: force, from: document, named: url.lastPathComponent,
                        through: recorder, effect: effect
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
                print(report.text)
            }
        }
    }

    // MARK: - Private

    /// Checks the consequence, then removes.
    ///
    /// - Parameters:
    ///   - name: The variable to remove.
    ///   - force: Whether to remove it despite references.
    ///   - document: The document being edited.
    ///   - fileName: The file's name, for the message when the variable is not there.
    ///   - recorder: The recorder the removal goes through.
    ///   - effect: Whether this is a rehearsal, which is what decides whether the
    ///     findings are collected and the revision dropped.
    /// - Returns: What was removed.
    /// - Throws: ``CommandFailure`` when no such variable exists, or when something
    ///   references it and `force` is `false`.
    private static func remove(
        _ name: String,
        force: Bool,
        from document: EditableDocument,
        named fileName: String,
        through recorder: ActivityRecorder,
        effect: WriteEffect
    ) throws -> Report {
        let findings = try effect.preview(of: document)
        guard let variable = document.variables?[name] else {
            throw CommandFailure(
                message: """
                No variable named \(name) in \(fileName). \
                `woodcase vars \(fileName)` lists the ones there are.
                """,
                exitCode: .usage
            )
        }
        let inUse = NameInUse.variable(name, in: document)
        if !force, !inUse.isEmpty {
            throw CommandFailure(
                message: inUse.sentence(in: .command(file: fileName)),
                exitCode: .usage
            )
        }
        try recorder.apply(.removeVariable(EditOperation.RemoveVariable(name: name)))
        return try Report(
            name: name,
            type: variable.type,
            revision: document.documentRevision,
            dryRun: effect == .dryRun,
            lint: findings?.introduced(in: document) ?? []
        )
    }
}
