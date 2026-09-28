//
//  VarsAxisAddCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// `woodcase vars axis add <file> mode=light,dark` — declare an axis, or widen one.
///
/// ```bash
/// woodcase vars axis add design.pen mode=light,dark
/// woodcase vars axis add design.pen mode=high-contrast   # appended to the same axis
/// ```
///
/// Options are appended, never reordered and never dropped: the first option of an
/// axis is the one that is active when nothing pins it, so re-ordering an axis would
/// silently change what the document renders as. `add` therefore only ever grows an
/// axis, and an option it already has is a no-op rather than a duplicate.
struct VarsAxisAdd: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Write: add a theme axis, or add options to one that exists.",
        discussion: """
        A write verb. Options are appended, never reordered and never dropped: an \
        axis's first option is the one that is active when nothing pins it, so \
        re-ordering one would silently change what the document renders as. An \
        option the axis already has is a no-op, not a duplicate.

          woodcase vars axis add design.pen mode=light,dark --as ana
        """
    )

    /// What one `axis add` did.
    struct Report: Friendly {
        /// Creates a report.
        ///
        /// - Parameters:
        ///   - axis: The axis as it now stands.
        ///   - added: The options this call added, in the order they were added.
        ///   - revision: The document revision the write left behind.
        ///   - dryRun: Whether this was a rehearsal. A rehearsal drops the revision —
        ///     the file is still at the one it had — and gains the marker and the
        ///     findings. See ``DryRunOption``.
        ///   - lint: The findings the write would introduce, from
        ///     ``Woodcase/LintPreview``. Only a dry run has any.
        init(
            axis: VariableFormatter.Axis,
            added: [String],
            revision: String,
            dryRun: Bool = false,
            lint: [LintFinding] = []
        ) {
            self.axis = axis
            self.added = added
            self.revision = dryRun ? nil : revision
            self.dryRun = dryRun ? true : nil
            self.lint = dryRun ? lint : nil
        }

        /// The axis as it now stands, with every option it holds.
        let axis: VariableFormatter.Axis

        /// The options this call added. Empty when the axis already had them all.
        let added: [String]

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

    @Argument(help: ArgumentHelp("The axis and its options.", valueName: "axis=option,…"))
    var assignment: VariableAssignment

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Adds the axis or its options and prints the axis as it now stands.
    func run() async throws {
        let url = try file.existingFile()
        let assignment = assignment
        let effect = preview.effect
        try await runReportingFailures(editing: url) {
            let outcome = try await PenFileTransaction.run(
                at: url, identity: identity.identity, effect: effect,
                fonts: .shared
            ) {
                document, recorder in
                do {
                    return try Self.add(assignment, to: document, through: recorder, effect: effect)
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

    /// The rows an `axis add` answers with.
    ///
    /// An `add` that names only options the axis already has changes nothing, and says
    /// so rather than printing an unchanged axis that reads like a write.
    ///
    /// A dry run leads with ``DryRunOption/marker``, prints no revision — it made none —
    /// and follows with the findings it would introduce.
    ///
    /// - Parameter report: What the write made.
    /// - Returns: The text to print.
    private static func text(_ report: Report) -> String {
        var lines: [String] = report.dryRun == true ? [DryRunOption.marker] : []
        lines += VariableFormatter.lines(for: [report.axis])
        if report.added.isEmpty {
            lines.append(
                "\(report.axis.name) already has \(report.axis.options.joined(separator: ", ")); "
                    + "nothing was added."
            )
        }
        if let revision = report.revision {
            lines.append("revision \(revision)")
        }
        if let lint = report.lint, !lint.isEmpty {
            lines.append(LintFormatter.text(lint))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    /// Creates the axis, or appends the options it does not have.
    ///
    /// - Parameters:
    ///   - assignment: The `axis=option,…` as typed.
    ///   - document: The document being edited.
    ///   - recorder: The recorder the theme operation goes through.
    ///   - effect: Whether this is a rehearsal, which is what decides whether the
    ///     findings are collected and the revision dropped.
    /// - Returns: What the write made.
    /// - Throws: ``CommandFailure`` when no option was named, and whatever the
    ///   operation itself throws.
    private static func add(
        _ assignment: VariableAssignment,
        to document: EditableDocument,
        through recorder: ActivityRecorder,
        effect: WriteEffect
    ) throws -> Report {
        let findings = try effect.preview(of: document)
        let options = assignment.options
        guard !options.isEmpty else {
            throw CommandFailure(
                message: """
                No options given for the axis \(assignment.name). \
                Write them as \(assignment.name)=light,dark.
                """,
                exitCode: .usage
            )
        }
        guard let existing = document.themes?[assignment.name] else {
            try recorder.apply(.addThemeAxis(EditOperation.AddThemeAxis(name: assignment.name, options: options)))
            return try report(
                VariableFormatter.Axis(name: assignment.name, options: options),
                added: options, in: document, effect: effect, findings: findings
            )
        }
        let added = options.filter { !existing.contains($0) }
        guard !added.isEmpty else {
            return try report(
                VariableFormatter.Axis(name: assignment.name, options: existing),
                added: [], in: document, effect: effect, findings: findings
            )
        }
        let widened = existing + added
        try recorder.apply(
            .updateThemeAxis(EditOperation.UpdateThemeAxis(name: assignment.name, options: widened))
        )
        return try report(
            VariableFormatter.Axis(name: assignment.name, options: widened),
            added: added, in: document, effect: effect, findings: findings
        )
    }

    /// The report for one of ``add(_:to:through:effect:)``'s three endings.
    ///
    /// - Parameters:
    ///   - axis: The axis as it now stands.
    ///   - added: The options this call added.
    ///   - document: The document, for the revision it now holds.
    ///   - effect: Whether this was a rehearsal.
    ///   - findings: The snapshot taken before the edit, or `nil` for a real write.
    /// - Returns: What the write made.
    /// - Throws: Whatever ``Woodcase/LintPreview/introduced(in:)`` throws.
    private static func report(
        _ axis: VariableFormatter.Axis,
        added: [String],
        in document: EditableDocument,
        effect: WriteEffect,
        findings: LintPreview?
    ) throws -> Report {
        try Report(
            axis: axis,
            added: added,
            revision: document.documentRevision,
            dryRun: effect == .dryRun,
            lint: findings?.introduced(in: document) ?? []
        )
    }
}
