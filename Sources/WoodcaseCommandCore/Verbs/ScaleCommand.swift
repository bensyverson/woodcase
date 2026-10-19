//
//  ScaleCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Scales nodes proportionally by one factor about one of the nine points of their union.
///
/// The verb is an adapter: it resolves the addresses, lays the file out, and applies the
/// operations ``Woodcase/EditPlanner/planScale(nodeIDs:by:anchor:in:layout:)`` plans in one
/// transaction, so one `woodcase undo` takes the whole scale back. What scales, and how each
/// node moves, is the library's.
struct ScaleCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "scale",
        abstract: "Write: scale nodes proportionally by one factor — sizes, type, strokes, radii, effects, spacing.",
        discussion: """
        An act verb: what an editor's Scale does. Everything that is a length grows \
        by the same factor and the nodes' children with them: position about the \
        anchor, width and height, font size and letter spacing, stroke widths and \
        dashes, corner radii, shadows and blurs, gap and padding. Proportional only, \
        so nothing is stretched. Sizing modes stay as they are: an auto text still \
        fits its words, a fill still fills. A value bound to a variable stays bound \
        and is listed as unscaled. Inside a component instance every write is an \
        override on the instance; the component is unchanged.

        --by takes a factor (2, 0.5) or a percentage (200%, 50%). --anchor names the \
        point of the nodes' union that stays still. A node inside another node named \
        is scaled once, with it.

        The report lists each bound value left unscaled. --json prints \
        {"operations", "unscaled", "revision"}.

        \(AddressArgument.addressForms)

        EXAMPLE
          woodcase scale design.pen Card --by 150% --as ana
          woodcase scale design.pen Hero/Logo Hero/Title --by 0.5 --anchor center --as ana
        """
    )

    /// What one scale did.
    struct Report: Friendly {
        /// How many edits the scale wrote.
        let operations: Int

        /// The values left unscaled because a variable supplies them.
        let unscaled: [ScalePlan.BoundValue]

        /// The document revision the write left behind, or `nil` for a dry run.
        let revision: String?

        /// `true` when nothing was written, `nil` when something was.
        let dryRun: Bool?
    }

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "The nodes to scale.")
    var nodes: [String]

    @Option(name: .long, parsing: .unconditional, help: "The factor: a number (2, 0.5) or a percentage (200%, 50%).")
    var by: String

    @Option(name: .long, help: "The point that stays still: \(ScaleAnchor.allCases.map(\.rawValue).joined(separator: ", ")).")
    var anchor: String = ScaleAnchor.topLeft.rawValue

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Resolves the nodes, plans the scale and applies it.
    func run() async throws {
        let url = try file.existingFile()
        let addresses = try nodes.map(AddressArgument.node)
        guard !addresses.isEmpty else {
            throw CommandFailure(message: "Name at least one node to scale.", exitCode: .usage)
        }
        let factor = try Self.factor(by)
        guard let anchor = ScaleAnchor(rawValue: anchor) else {
            let names = ScaleAnchor.allCases.map(\.rawValue).joined(separator: ", ")
            throw CommandFailure(message: "--anchor \(anchor) is not an anchor; use one of \(names).", exitCode: .usage)
        }
        let effect = preview.effect
        let wantsJSON = output.json

        try await runReportingFailures(editing: url) {
            let outcome = try await CommandTransaction.run(
                at: url, identity: identity.identity, effect: effect, fonts: .shared
            ) { document, recorder in
                do {
                    let ids = try addresses.map { try GroupCommand.plannerID(of: $0, in: document) }
                    let plan = try EditPlanner.planScale(
                        nodeIDs: ids, by: factor, anchor: anchor, in: document,
                        layout: GroupCommand.layout(of: document)
                    )
                    for operation in plan.operations {
                        try recorder.apply(operation)
                    }
                    return Report(
                        operations: plan.operations.count,
                        unscaled: plan.unscaled,
                        revision: effect == .dryRun ? nil : document.documentRevision,
                        dryRun: effect == .dryRun ? true : nil
                    )
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
            }
            OutsideWriteNote.report(outcome, json: wantsJSON)
            try print(wantsJSON ? CanonicalJSON.text(outcome.value) : Self.text(outcome.value))
        }
    }

    /// The factor `--by` names: a number, or a percentage of the current size.
    static func factor(_ text: String) throws -> Double {
        let percent = text.hasSuffix("%")
        let number = Double(percent ? String(text.dropLast()) : text)
        guard let number, number.isFinite, number > 0 else {
            throw CommandFailure(
                message: "--by \(text) is not a factor; write a positive number (2, 0.5) or a percentage (200%, 50%).",
                exitCode: .usage
            )
        }
        return percent ? number / 100 : number
    }

    /// The report as lines.
    static func text(_ report: Report) -> String {
        var lines: [String] = report.dryRun == true ? [DryRunOption.marker] : []
        lines.append("scaled with \(report.operations) edit\(report.operations == 1 ? "" : "s")")
        for value in report.unscaled {
            lines.append("unscaled \(value.nodeID) \(value.property)  bound to $\(value.variable)")
        }
        if let revision = report.revision {
            lines.append("revision \(revision)")
        }
        return lines.joined(separator: "\n")
    }
}
