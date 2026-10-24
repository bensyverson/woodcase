//
//  GroupCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Wraps nodes in a new group, or in a new free frame, without moving them on the canvas.
///
/// The verb is an adapter: it resolves the addresses, lays the file out, and applies the
/// operations ``Woodcase/EditPlanner/planGroup(nodeIDs:kind:named:in:layout:)`` plans in one
/// transaction, so one `woodcase undo` takes the whole group back. Where the wrapper goes
/// and how each member is re-placed is the library's.
struct GroupCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "group",
        abstract: "Write: wrap nodes in a new group, or a frame with --frame, keeping them where they are.",
        discussion: """
        An act verb: what an editor's Group (⌘G) and Frame Selection (⌥⌘G) do. \
        The wrapper goes into the parent of the front-most node — the one drawn on \
        top, the last in document order — at its index; nodes from other parents \
        move in. Nothing moves on the canvas: each node's x and y, and its turn and \
        flips under a turned or flipped parent, are rewritten to keep it where it is \
        drawn. In a stack the wrapper takes the front-most node's place in the flow, \
        and the nodes become its free children where they were drawn.

        A group has no box of its own; --frame wraps in a frame with layout none, \
        no fill and no clip, sized to the nodes. A node inside another node named \
        is left where it is. A node inside a component instance is refused, and so \
        is a wrap that would put a component inside itself.

        The report names the wrapper. --json prints {"id", "path", "revision"}.

        \(AddressArgument.addressForms)

        EXAMPLE
          woodcase group design.pen Card/Title Card/Subtitle --as ana
          woodcase group design.pen Hero Footer --frame --as ana
        """
    )

    /// What one group did.
    struct Report: Friendly {
        /// The wrapper's id.
        let id: String

        /// The wrapper's name path.
        let path: String

        /// The document revision the write left behind, or `nil` for a dry run.
        let revision: String?

        /// `true` when nothing was written, `nil` when something was.
        let dryRun: Bool?
    }

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "The nodes to wrap.")
    var nodes: [String]

    @Flag(name: .long, help: "Wrap in a free frame sized to the nodes, rather than a group.")
    var frame: Bool = false

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Resolves the nodes, plans the group and applies it.
    func run() async throws {
        let url = try file.existingFile()
        let addresses = try nodes.map(AddressArgument.node)
        guard !addresses.isEmpty else {
            throw CommandFailure(message: "Name at least one node to group.", exitCode: .usage)
        }
        let kind: WrapKind = frame ? .frame : .group
        let effect = preview.effect
        let wantsJSON = output.json

        try await runReportingFailures(editing: url) {
            let outcome = try await CommandTransaction.run(
                at: url, identity: identity.identity, effect: effect, fonts: .shared
            ) { document, recorder in
                do {
                    let ids = try addresses.map { try Self.plannerID(of: $0, in: document) }
                    let plan = try EditPlanner.planGroup(
                        nodeIDs: ids, kind: kind, in: document, layout: Self.layout(of: document)
                    )
                    for operation in plan.operations {
                        try recorder.apply(operation)
                    }
                    return Report(
                        id: plan.wrapperID,
                        path: document.namePath(of: plan.wrapperID),
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

    /// The id the planner takes for an address: a stored node's own, or the expanded id
    /// of a node inside an instance, which the planner refuses by name.
    static func plannerID(of address: NodeAddress, in document: EditableDocument) throws -> String {
        let resolved = try document.resolve(address)
        switch resolved {
        case let .node(id): return id
        case .instanceDescendant: return document.expandedID(of: resolved)
        }
    }

    /// The file laid out as it stands, for the planner's canvas geometry.
    static func layout(of document: EditableDocument) -> PenLayoutState {
        PenLayoutState(document: PenVariableResolver.resolve(document.expandedDocument().0))
    }

    /// The report as lines.
    static func text(_ report: Report) -> String {
        var lines: [String] = report.dryRun == true ? [DryRunOption.marker] : []
        lines.append("\(report.path)  \(report.id)")
        if let revision = report.revision {
            lines.append("revision \(revision)")
        }
        return lines.joined(separator: "\n")
    }
}
