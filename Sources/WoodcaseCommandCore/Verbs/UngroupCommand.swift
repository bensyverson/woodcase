//
//  UngroupCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Takes a group or a frame apart, keeping its children where they are on the canvas.
///
/// The verb is an adapter: it resolves the address, lays the file out, and applies the
/// operations ``Woodcase/EditPlanner/planUngroup(groupID:in:layout:)`` plans in one
/// transaction, so one `woodcase undo` puts the group back.
struct UngroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ungroup",
        abstract: "Write: take a group or frame apart, keeping its children where they are.",
        discussion: """
        An act verb: what an editor's Ungroup (⇧⌘G) does. The children go to the \
        group's parent at its index, in their order, and the group is removed. The \
        group's position, turn and flips are folded into each child, so nothing moves \
        on the canvas; in a stack, the children join the flow there instead. \
        Ungrouping a frame works the same, and its fills, strokes and clip go with it.

        A connector attached to the group itself would be left naming nothing, so it \
        goes too, in the same edit; connectors attached to the children stay. One \
        undo brings both back.

        A node inside a component instance is refused, and so is a component that \
        has instances.

        The report names the children and any connector removed. --json prints \
        {"ids", "deletedConnectors", "connectorNote", "revision"}.

        \(AddressArgument.addressForms)

        EXAMPLE
          woodcase ungroup design.pen Card/Header --as ana
        """
    )

    /// What one ungroup did.
    struct Report: Friendly {
        /// The children's ids, in their new order.
        let ids: [String]

        /// The connectors removed because they were attached to the group itself, or `nil`
        /// when there were none.
        let deletedConnectors: [String]?

        /// The sentence naming the connectors removed, or `nil` when there were none.
        let connectorNote: String?

        /// The document revision the write left behind, or `nil` for a dry run.
        let revision: String?

        /// `true` when nothing was written, `nil` when something was.
        let dryRun: Bool?
    }

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "The group or frame to take apart.")
    var node: String

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Resolves the node, plans the ungroup and applies it.
    func run() async throws {
        let url = try file.existingFile()
        let address = try AddressArgument.node(node)
        let effect = preview.effect
        let wantsJSON = output.json

        try await runReportingFailures(editing: url) {
            let outcome = try await CommandTransaction.run(
                at: url, identity: identity.identity, effect: effect, fonts: .shared
            ) { document, recorder in
                do {
                    let id = try GroupCommand.plannerID(of: address, in: document)
                    let children = document.childIDs(of: id)
                    let connectors = EditPlanner.connectorIDs(attachedTo: [id], in: document)
                    let names = connectors.map { document.namePath(of: $0) }
                    let group = document.node(id: id)?.common.name ?? id
                    let operations = try EditPlanner.planUngroup(
                        groupID: id, in: document, layout: GroupCommand.layout(of: document)
                    )
                    for operation in operations {
                        try recorder.apply(operation)
                    }
                    return Report(
                        ids: children,
                        deletedConnectors: connectors.isEmpty ? nil : connectors,
                        connectorNote: Self.note(removing: names, from: group),
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

    /// The sentence naming the connectors an ungroup removed with the group.
    ///
    /// - Parameters:
    ///   - names: The connectors' name paths.
    ///   - group: The group's name.
    /// - Returns: The sentence, or `nil` for none.
    static func note(removing names: [String], from group: String) -> String? {
        guard !names.isEmpty else { return nil }
        let subject = names.count == 1 ? "1 connector" : "\(names.count) connectors"
        return "also removed \(subject) attached to \(group): \(names.joined(separator: ", "))"
    }

    /// The report as lines.
    static func text(_ report: Report) -> String {
        var lines: [String] = report.dryRun == true ? [DryRunOption.marker] : []
        lines.append("ungrouped \(report.ids.joined(separator: ", "))")
        if let note = report.connectorNote {
            lines.append(note)
        }
        if let revision = report.revision {
            lines.append("revision \(revision)")
        }
        return lines.joined(separator: "\n")
    }
}
