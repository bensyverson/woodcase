//
//  ReplaceCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Swaps a node's whole subtree for an authored one, keeping the node's place.
struct ReplaceCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "replace",
        abstract: "Write: swap a node's subtree for a new one, in place.",
        discussion: """
        An act verb, and the one for "rebuild this". The node keeps its id, its \
        parent and its index among its siblings; everything under it — its own \
        properties included — becomes what the subtree says. That is what a delete \
        and an add cannot do together: the id would change, and every path, \
        `--rev` and component reference pointing at it would go stale.

        The subtree is .pen JSON, read from a file with -F (or from standard input \
        with `-F -`), exactly as `woodcase add` reads one. Ids inside it are \
        optional and are kept when written; an id the *replaced* subtree holds \
        today may be reused, because it goes away with it. The root's own id is \
        the target's whatever you write — leave it out, or write the target's id; \
        a different one is refused rather than quietly ignored.

        Every node in the subtree needs a "name", for the same reason `add` \
        insists on one: an unnamed node cannot be addressed by path afterwards.

        Rebuilding a reusable component is the point of the verb, and every \
        instance follows the new contents. But an instance's overrides are keyed \
        by the DEFINITION'S CHILD IDS, and a replacement mints a new id for every \
        node it does not write one for — so every override whose id the \
        replacement does not carry forward is dropped, with no warning and no \
        lint finding. `woodcase get <definition> --instances` lists who would \
        lose them. Write the old ids into the replacement to keep those \
        overrides; better still, edit a live definition in place — `set` a child \
        (renaming one is free, because names are not the key), `add` or `cp` one \
        in, `rm` one out — and use `replace` on definitions nothing instances yet.

        Changing what *kind* of node the definition is, while instances point at \
        it, is refused: the instances would silently draw something else.

        The answer is the new subtree's name → id tree, then the node's revision \
        and the document's — the same shape `add` prints, because the next command \
        needs the same three things.

        \(AddressArgument.addressForms)

        EXAMPLE
          woodcase get design.pen Card --json > card.json   # keep the old one
          echo '{"type":"frame","name":"Card","layout":"vertical","children":[
                  {"type":"text","name":"Title","content":"Rebuilt"}]}' \\
            | woodcase replace design.pen Card -F - --rev 4f2a1b0c9d8e7f60 --as ana
          woodcase tree design.pen Card                     # verify
        """
    )

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "The node whose subtree is being swapped.")
    var node: String

    @Option(
        name: .customShort("F"),
        help: ArgumentHelp("A .pen subtree as JSON. `-` reads standard input.", valueName: "file")
    )
    var subtreeFile: String

    @OptionGroup var revision: RevisionOption
    @OptionGroup var premise: GuardOption
    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    func run() async throws {
        let url = try file.existingFile()
        let target = try AddressArgument.node(node)
        let replacement = try subtree()
        let expected = revision.rev
        let pins = try premise.guards()
        let effect = preview.effect
        let writer = identity.identity
        let wantsJSON = output.json

        try await runReportingFailures(editing: url) {
            let outcome = try await PenFileTransaction.run(at: url, identity: writer, effect: effect, fonts: .shared) { document, recorder in
                do {
                    let findings = try effect.preview(of: document)
                    let result = try BatchApplier.applyOne(
                        .replace(BatchOperation.ReplaceOp(
                            target: target, node: replacement, rev: expected, guards: pins
                        )),
                        to: document,
                        recorder: recorder,
                        log: ActivityLogLocation.log(for: url),
                        file: url
                    )
                    return try WriteReport(
                        created: result.created,
                        path: result.path,
                        id: result.created.first?.id,
                        nodeRevision: result.created.first.flatMap { document.revision(of: $0.id) },
                        documentRevision: document.documentRevision,
                        node: result.node,
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

    /// The subtree to swap in, decoded from `-F`.
    ///
    /// - Returns: The node, with an empty id marking anything the author left out.
    /// - Throws: ``CommandFailure`` with ``ExitCode/targetFailure`` when the file
    ///   cannot be read, or ``ExitCode/usage`` when it is not a .pen node.
    private func subtree() throws -> PenNode {
        let data = try InputFile.data(at: subtreeFile)
        do {
            return try PenSubtreeDecoder.node(from: JSONDecoder().decode(AnyCodable.self, from: data))
        } catch {
            throw CommandFailure(
                message: "\(subtreeFile) is not a .pen subtree: \(error). A subtree is one JSON "
                    + #"object with a "type" and a "name", and optional "children"."#,
                exitCode: .usage
            )
        }
    }
}
