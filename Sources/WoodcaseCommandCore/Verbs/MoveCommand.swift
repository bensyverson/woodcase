//
//  MoveCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Relocates a node to a new parent or a new position.
struct MoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mv",
        abstract: "Write: move a node to another parent, or to another position.",
        discussion: """
        An act verb. The node keeps everything it had; only where it sits changes. \
        Naming the parent it is already in reorders it there, and `document` makes \
        it a root.

        A node cannot move inside itself, and it cannot move into a component \
        instance — an instance's children belong to the component, so there would be \
        nowhere to store them. Both are refused with the reason.

        \(AddressArgument.addressForms)

        EXAMPLE
          woodcase mv design.pen Card/Badge Card/Header --at 0 --as ana
        """
    )

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "The node to move.")
    var node: String

    @Argument(help: "The new parent, or `document` for the document root.")
    var parent: String

    @OptionGroup var position: PositionOption
    @OptionGroup var revision: RevisionOption
    @OptionGroup var premise: GuardOption
    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    func run() async throws {
        let url = try file.existingFile()
        let target = try AddressArgument.node(node)
        let parentAddress = try AddressArgument.parent(parent)
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
                    let id = try document.resolve(target).targetID
                    let result = try BatchApplier.applyOne(
                        .mv(BatchOperation.MoveOp(
                            target: target, parent: parentAddress, at: index,
                            rev: expected, guards: pins
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
                            path: result.path ?? document.namePath(of: id),
                            id: id,
                            nodeRevision: document.revision(of: id),
                            documentRevision: document.documentRevision,
                            warnings: warnings,
                            node: result.node,
                            divergences: result.divergences,
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
}
