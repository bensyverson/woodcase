//
//  RemoveCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Deletes a node and everything under it.
struct RemoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rm",
        abstract: "Write: delete a node and its descendants.",
        discussion: """
        An act verb, and the one whose consequence can exceed its target. Deleting a \
        reusable component while instances of it exist is refused, listing the \
        instances by path — they would silently become plain frames. --detach is how \
        that consequence is opted into: every instance is detached into a real copy \
        of what it showed, and only then is the component deleted.

        The answer names what went and the document's new revision. There is no node \
        revision to report, because there is no longer a node.

        \(AddressArgument.addressForms)

        EXAMPLE
          woodcase rm design.pen Library/Button --detach --as ana
        """
    )

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "The node to delete.")
    var node: String

    @Flag(
        name: .long,
        help: "Detach every instance of this component before deleting it."
    )
    var detach: Bool = false

    @OptionGroup var revision: RevisionOption
    @OptionGroup var premise: GuardOption
    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    func run() async throws {
        let url = try file.existingFile()
        let target = try AddressArgument.node(node)
        let detaching = detach
        let expected = revision.rev
        let pins = try premise.guards()
        let effect = preview.effect
        let writer = identity.identity
        let wantsJSON = output.json

        try await runReportingFailures(editing: url) {
            let outcome = try await PenFileTransaction.run(at: url, identity: writer, effect: effect, fonts: .shared) { document, recorder in
                do {
                    let findings = try effect.preview(of: document)
                    // The path has to be read before the delete: afterwards there is no
                    // node to name, and `#id` is not what the caller typed.
                    let id = try document.resolve(target).targetID
                    let path = document.namePath(of: id)
                    let result = try BatchApplier.applyOne(
                        .rm(BatchOperation.RemoveOp(
                            target: target, detach: detaching, rev: expected, guards: pins
                        )),
                        to: document,
                        recorder: recorder,
                        log: ActivityLogLocation.log(for: url),
                        file: url
                    )
                    return try WriteReport(
                        path: path,
                        id: id,
                        documentRevision: document.documentRevision,
                        divergences: result.divergences,
                        dryRun: effect == .dryRun,
                        lint: findings?.introduced(in: document) ?? []
                    ).rendered(json: wantsJSON)
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
            }
            OutsideWriteNote.report(outcome, json: wantsJSON)
            print(outcome.value)
        }
    }
}
