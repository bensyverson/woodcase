//
//  PasteCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Takes a clip — what `woodcase clip --json` prints — into a .pen file.
///
/// The verb is an adapter: it reads the clip, resolves the one placement it was given to a
/// ``Woodcase/PasteTarget``, and applies the operations
/// ``Woodcase/PenClip/plan(into:at:)`` plans, in one transaction — so one `woodcase undo`
/// takes the whole paste back. Every decision about what is reused, renamed or refused is
/// the library's.
struct PasteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "paste",
        abstract: "Write: take a clip from `woodcase clip --json` into a .pen file.",
        discussion: """
        An act verb, and the other half of `clip`: what an editor's Paste does. The \
        clip is the JSON `woodcase clip --json` prints, {"contentIDs": […], \
        "document": {…}}; `-` reads it from standard input.

        Where the copies go — pass at most one:
          --into <container>  after its last child: in a stack they join the flow; in a \
        free container each keeps the offset it had in the parent it was copied out of \
        (its canvas position, in the container's coordinates, when it was a root), or \
        they are centered in it when that would miss it
          --after <node>      right after the node in its parent: in a stack, in the \
        flow; elsewhere to its right, top-aligned
          --at x,y            on the canvas, as roots, centered on the point
          --in-place          on the canvas, as roots, where they were copied (the default)

        --into and --after also take a slot of an instance (Card/List), or a frame or \
        node in its content: the copies join the instance's fill, written as one \
        override of the slot. Anywhere else inside an instance is refused.

        Every id is new. A component or variable the file already has with the same \
        name and the same definition is reused, so pasting twice never duplicates a \
        component; one whose name the file holds with a different definition comes \
        along renamed (Button 2, $primary-2) and every use in the paste follows. \
        Components the file lacks land as roots to the right of everything on its \
        canvas. A paste that would make components contain each other is refused, \
        naming the loop, and nothing is written.

        Connections land at the top level, where Pen keeps them, wherever the copies \
        go — in a slot, their ends name the copies through the instance (Card/k3Fq9). A connector the clip carried — one whose two ends were both inside the \
        copied nodes — is attached to the pasted copies. A connector with an end that \
        would name a node neither the paste nor the file holds is left out, so none \
        points at nothing.

        The report names the new roots, the connectors attached and any left out, \
        then what was reused and what was renamed. --json prints the same as an object.

        \(AddressArgument.addressForms)

        EXAMPLE
          woodcase clip source.pen Buy --json > clip.json
          woodcase paste design.pen clip.json --into Page/Card --as ana
          woodcase clip design.pen Hero --json | woodcase paste other.pen - --at 0,0 --as ana
        """
    )

    /// What one paste did.
    struct Report: Friendly {
        /// The new ids of the copied roots, in clip order.
        let insertedRootIDs: [String]

        /// Clip component id → the file's component used in its place.
        let reusedComponents: [String: String]

        /// The components that came along under a new name.
        let renamedComponents: [PastePlan.Rename]

        /// The clip's variables the file already had.
        let reusedVariables: [String]

        /// The variables that came along under a new name.
        let renamedVariables: [PastePlan.Rename]

        /// The new ids of the connectors the clip carried, attached to the copies, or `nil`
        /// when it carried none.
        let insertedConnectorIDs: [String]?

        /// The clip ids of the connectors left out because an end would name nothing, or
        /// `nil` when none was.
        let droppedConnectorIDs: [String]?

        /// The document revision the write left behind, or `nil` for a dry run.
        let revision: String?

        /// `true` when nothing was written, `nil` when something was.
        let dryRun: Bool?
    }

    @Argument(help: "The .pen file to paste into.")
    var file: PenFilePath

    @Argument(help: "The clip: a file `woodcase clip --json` wrote, or `-` for standard input.")
    var clip: String

    @Option(name: .long, help: ArgumentHelp("Paste after the container's last child.", valueName: "container"))
    var into: String?

    @Option(name: .long, help: ArgumentHelp("Paste right after a node, in its parent.", valueName: "node"))
    var after: String?

    @Option(name: .long, help: ArgumentHelp("Paste on the canvas, centered on a point.", valueName: "x,y"))
    var at: String?

    @Flag(name: .customLong("in-place"), help: "Paste on the canvas where the nodes were copied (the default).")
    var inPlace: Bool = false

    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    /// Reads the clip, plans the paste and applies it.
    func run() async throws {
        let url = try file.existingFile()
        let placement = try placement()
        let clip = try Self.clip(from: InputFile.data(at: clip), named: clip)
        let effect = preview.effect
        let wantsJSON = output.json

        try await runReportingFailures(editing: url) {
            let outcome = try await CommandTransaction.run(
                at: url, identity: identity.identity, effect: effect, fonts: .shared
            ) { document, recorder in
                do {
                    let target = try Self.target(placement, in: document)
                    let plan = try clip.plan(into: document, at: target)
                    for operation in plan.operations {
                        try recorder.apply(operation)
                    }
                    return Report(
                        insertedRootIDs: plan.insertedRootIDs,
                        reusedComponents: plan.reusedComponents,
                        renamedComponents: plan.renamedComponents,
                        reusedVariables: plan.reusedVariables,
                        renamedVariables: plan.renamedVariables,
                        insertedConnectorIDs: plan.insertedConnectorIDs.isEmpty ? nil : plan.insertedConnectorIDs,
                        droppedConnectorIDs: plan.droppedConnectorIDs.isEmpty ? nil : plan.droppedConnectorIDs,
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

    // MARK: - Placement

    /// Where the copies go, as typed: one of the four, still as addresses.
    enum Placement: Friendly {
        /// `--into`: after the container's last child.
        case into(NodeAddress)
        /// `--after`: right after the node, in its parent.
        case after(NodeAddress)
        /// `--at`: on the canvas, centered on the point.
        case at(PenPoint)
        /// `--in-place`, or nothing: on the canvas, where the nodes were copied.
        case inPlace
    }

    /// The one placement this invocation gave.
    ///
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` for more than one, or a
    ///   point that is not `x,y`.
    func placement() throws -> Placement {
        let given = [into.map { _ in "--into" }, after.map { _ in "--after" }, at.map { _ in "--at" }, inPlace ? "--in-place" : nil]
            .compactMap(\.self)
        guard given.count <= 1 else {
            throw CommandFailure(
                message: "\(given.joined(separator: " and ")) each say where the paste goes; pass one "
                    + "(--into <container>, --after <node>, --at x,y or --in-place).",
                exitCode: .usage
            )
        }
        if let into { return try .into(AddressArgument.node(into)) }
        if let after { return try .after(AddressArgument.node(after)) }
        if let at { return try .at(Self.point(at)) }
        return .inPlace
    }

    /// Parses `x,y`.
    private static func point(_ raw: String) throws -> PenPoint {
        let parts = raw.split(separator: ",").map { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == 2, let x = parts[0], let y = parts[1] else {
            throw CommandFailure(message: "--at takes a canvas point as x,y — for example --at 0,0 — not \(raw).", exitCode: .usage)
        }
        return PenPoint(x: x, y: y)
    }

    /// The placement against the document: each address resolved to a stored node, or to
    /// the expanded id of a node drawn inside an instance — a slot, or slot content —
    /// which the planner pastes into the instance's fill or refuses.
    ///
    /// - Throws: Whatever resolving throws.
    private static func target(_ placement: Placement, in document: EditableDocument) throws -> PasteTarget {
        switch placement {
        case let .into(address): try .inside(containerID: nodeID(address, in: document))
        case let .after(address): try .after(siblingID: nodeID(address, in: document))
        case let .at(point): .centered(on: point, in: nil)
        case .inPlace: .inPlace
        }
    }

    /// A stored node's id, or the id a node drawn inside an instance answers to by its
    /// instance and key (`Filled/List`).
    private static func nodeID(_ address: NodeAddress, in document: EditableDocument) throws -> String {
        switch try document.resolve(address) {
        case let .node(id):
            id
        case let .instanceDescendant(refID, key):
            refID + String(NodeAddress.separator) + key
        }
    }

    // MARK: - Reading and printing

    /// Decodes a clip.
    ///
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` for anything but the JSON
    ///   `woodcase clip --json` prints — a bare .pen included, which cannot say which of
    ///   its roots were copied.
    static func clip(from data: Data, named name: String) throws -> PenClip {
        do {
            return try JSONDecoder().decode(PenClip.self, from: data)
        } catch {
            throw CommandFailure(
                message: "\(name == InputFile.standardInput ? "standard input" : name) is not a clip. "
                    + "Write one with `woodcase clip <file> <nodes…> --json`: the bare .pen `clip` prints "
                    + "without --json cannot say which roots were copied and which are components "
                    + "carried along.",
                exitCode: .usage
            )
        }
    }

    /// The report as lines.
    static func text(_ report: Report) -> String {
        var lines: [String] = report.dryRun == true ? [DryRunOption.marker] : []
        lines.append("pasted \(report.insertedRootIDs.joined(separator: ", "))")
        if let connectors = report.insertedConnectorIDs {
            lines.append("attached connectors \(connectors.joined(separator: ", "))")
        }
        if let dropped = report.droppedConnectorIDs {
            lines.append("left out connectors \(dropped.joined(separator: ", ")), an end naming nothing here")
        }
        if !report.reusedComponents.isEmpty {
            lines.append("reused components \(report.reusedComponents.values.sorted().joined(separator: ", "))")
        }
        for rename in report.renamedComponents {
            lines.append("renamed component \(rename.from) → \(rename.to)")
        }
        if !report.reusedVariables.isEmpty {
            lines.append("reused variables \(report.reusedVariables.map { "$" + $0 }.joined(separator: ", "))")
        }
        for rename in report.renamedVariables {
            lines.append("renamed variable $\(rename.from) → $\(rename.to)")
        }
        if let revision = report.revision {
            lines.append("revision \(revision)")
        }
        return lines.joined(separator: "\n")
    }
}
