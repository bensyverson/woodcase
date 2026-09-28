//
//  OverrideCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Overrides a property on a node inside a component instance.
struct OverrideCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "override",
        abstract: "Write: override properties inside a component instance, or on its root.",
        discussion: """
        An act verb. A node inside an instance has no storage of its own: what you \
        write here becomes an entry in the instance's `descendants` map, exactly as \
        the format stores it. Address it by stepping through the instance — \
        Orders/Value, or Orders/Badge/Count for a nested one. A name path into an \
        instance names every frame of the component's tree; only an id may skip one.

        Addressing the INSTANCE ITSELF, with no path after it, writes the component \
        ROOT's own properties as this instance shows them — the format's root \
        overrides. `set` on the same address still writes the ref node: where the \
        instance sits and whether it draws are its own, so common.x, common.opacity \
        and the rest belong to `set`, and everything the component root draws with \
        belongs here.

        Property names here are stored as RAW .pen names — "content", not \
        "kind.content" — because that is the vocabulary that map's keys use. A \
        property path is translated for you, so either vocabulary is accepted and \
        what comes back is the raw one.

        A key may also be a name the component PUBLISHES. A component declares its \
        parameters in common.metadata._props as name → the name path of the node the \
        value belongs to, which is what code generation reads; write the name and the \
        value lands there — `label=Hi` on the instance means the content of whatever \
        node label names. `woodcase get <component>` lists them. A name the addressed \
        node already has a property of is the property, and the answer says so. A \
        name whose declared path resolves to nothing is refused before anything is \
        written.

        A value the node cannot take is refused rather than stored: an override that \
        will not merge is dropped when the instance expands, and a dropped override \
        reads back forever without ever drawing.

        --unset KEY REMOVES an override, so the component's own value shows again. \
        That is not what key=null does: a null is *stored*, and clears the property \
        wherever this instance draws — the override is still there, and `get` still \
        reports it. Pass --unset once per key; it may be given with or without \
        key=value, and never for the same key as one.

        \(PropertyAssignment.valueRules)

        A leading $ means here exactly what it means everywhere else, because the rule \
        belongs to the property and not to the verb that wrote it. content=$brand \
        stores a reference to the variable brand; '\\$brand' stores the literal \
        $brand, and a \\$ anywhere further into the string loses its backslash the \
        same way, so 'Total: \\$30' draws Total: $30. A bare $name the document \
        defines NOWHERE is forgiven in content alone — '$30.00' is the price it looks \
        like, and lint says nothing — while a name the document does define still \
        resolves, still reports as unresolved-variable when nothing resolves it, and \
        in any other property a bare $name naming nothing stays a dangling reference \
        that draws nothing. Single-quote the backslash or the shell eats it.

        Properties can also come from a JSON object with -F, and a key=value on the \
        command line wins over the same key in that file.

        The answer names the *instance*, because that is where the override is \
        stored and what --rev guards.

        EXAMPLES
          woodcase override design.pen Orders/Value content=42 --as ana
          woodcase override design.pen Orders width=320
          woodcase override design.pen Orders label=Checkout
          woodcase override design.pen Orders/Value --unset fontSize
        """
    )

    @Argument(help: "The .pen file to edit.")
    var file: PenFilePath

    @Argument(help: "An instance, or a path stepping through one, like Orders/Value.")
    var node: String

    @Argument(help: "Overrides to write, as key=value with raw .pen property names.")
    var assignments: [String] = []

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Remove this override, so the component's value shows again. Repeatable.",
            valueName: "key"
        )
    )
    var unset: [String] = []

    @Option(
        name: .customShort("F"),
        help: ArgumentHelp("A JSON object of overrides. `-` reads standard input.", valueName: "file")
    )
    var propertiesFile: String?

    @OptionGroup var revision: RevisionOption
    @OptionGroup var premise: GuardOption
    @OptionGroup var preview: DryRunOption
    @OptionGroup var identity: IdentityOptions<Identity.Attribution>
    @OptionGroup var output: OutputOptions

    func run() async throws {
        let url = try file.existingFile()
        let target = try AddressArgument.node(node)
        let properties = try PropertyAssignment.properties(from: assignments, file: propertiesFile)
        guard !properties.isEmpty || !unset.isEmpty else {
            throw CommandFailure(
                message: "override needs at least one key=value to write or --unset key to "
                    + "remove, using raw .pen property names (content, not kind.content). "
                    + "\(PropertyAssignment.valueRules)",
                exitCode: .usage
            )
        }
        try Self.refuseOverlap(between: properties, and: unset)
        let expected = revision.rev
        let pins = try premise.guards()
        let effect = preview.effect
        let writer = identity.identity
        let wantsJSON = output.json

        try await runReportingFailures(editing: url) {
            let outcome = try await PenFileTransaction.run(at: url, identity: writer, effect: effect, fonts: .shared) { document, recorder in
                do {
                    let findings = try effect.preview(of: document)
                    let instanceID = try document.resolve(target).targetID
                    let result = try BatchApplier.applyOne(
                        .override(BatchOperation.OverrideOp(
                            target: target, props: properties, unset: unset,
                            rev: expected, guards: pins
                        )),
                        to: document,
                        recorder: recorder,
                        log: ActivityLogLocation.log(for: url),
                        file: url
                    )
                    return try WriteReport(
                        path: result.path ?? document.namePath(of: instanceID),
                        id: instanceID,
                        nodeRevision: document.revision(of: instanceID),
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

    /// Refuses a command that both writes and removes the same key.
    ///
    /// The two are opposites, and an order of application is not something a caller
    /// should have to know: whichever won, the other half of what was typed did
    /// nothing. Judged after translation, so `kind.content=x --unset content` is caught
    /// as the one key it is.
    ///
    /// - Parameters:
    ///   - properties: The `key=value` assignments, keyed as written.
    ///   - unset: The keys to remove, as written.
    /// - Throws: ``CommandFailure`` with ``ExitCode/usage`` naming the key.
    private static func refuseOverlap(
        between properties: [String: AnyCodable],
        and unset: [String]
    ) throws {
        let written = Set(properties.keys.map { NodePropertyCodec.rawKey(for: $0) })
        for key in unset where written.contains(NodePropertyCodec.rawKey(for: key)) {
            throw CommandFailure(
                message: "\(key) is both assigned and unset. Write one or the other: a "
                    + "key=value stores a value, --unset removes the override entirely.",
                exitCode: .usage
            )
        }
    }
}
