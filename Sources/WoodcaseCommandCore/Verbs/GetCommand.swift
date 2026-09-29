//
//  GetCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Prints one node as `.pen` JSON, with the revision a write must quote back.
///
/// `woodcase tree` says what is there; this says what one node *is*. The JSON is the
/// file's own canonical form, so it diffs against the file it came from and can be
/// pasted back into one.
struct Get: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read: one node of a .pen file as canonical .pen JSON, with its revision.",
        discussion: """
        A read verb: it takes a shared lock, writes nothing, and leaves the file's \
        bytes and modification date alone.

        The first line is the node's id-form address, its name path, and its \
        revision — quote that back with --rev on the write that follows. The JSON is \
        the node as the file stores it, without its children: `woodcase tree` is the \
        structural read.

        --json wraps the same answer as one object instead: the node under "node", \
        beside "revision" — and "props" when the node publishes parameters. That is \
        the NodeReport doc.get returns in `woodcase js`.

        --expand prints the node as it renders instead, children and all: a component \
        instance appears with the component's subtree under it, overrides applied, \
        every id prefixed by the instance's own. Those descendant ids \
        (`Nav01/Bdg01/Cnt01`) are addresses every other verb accepts; the instance's \
        own root is an expansion artifact (`Nav01/Btn01`) and is still addressed as \
        the ref, which is what the header line prints. An address that points \
        *inside* an instance is always answered this way, because it names no stored \
        node; its revision is the instance's, since that is where an override to it \
        is written. Variables are left as written — `woodcase tree --props` reports \
        resolved values.

        --instances asks the opposite question of a reusable component: which `ref` \
        nodes draw it. One row per instance — address, id and its own revision, in \
        document order — under the same header line, so an agent about to override \
        one already holds the pin that write needs. It prints no node, so it does not \
        combine with --expand, and a node that is not reusable is refused rather than \
        answered with an empty list.

          woodcase get design.pen Dashboard/Header/Title --json
          woodcase get design.pen Button --instances

        """
    )

    @Argument(help: "The .pen file to read.")
    var file: PenFilePath

    @Argument(help: "The node — an id, a name path, or an instance path.")
    var node: String

    @Flag(name: .long, help: "Print the node as it renders: instances expanded, overrides applied.")
    var expand: Bool = false

    @Flag(name: .long, help: "List every instance of this reusable component instead of the node.")
    var instances: Bool = false

    @OptionGroup var output: OutputOptions

    /// Reads the file and prints the node, or its instances.
    func run() async throws {
        let url = try file.existingFile()
        guard !(instances && expand) else {
            throw CommandFailure(
                message: "--instances lists the refs that draw a component and prints no node, so "
                    + "--expand has nothing to expand. Run one or the other.",
                exitCode: .usage
            )
        }

        try await runReportingFailures(editing: url) {
            let diagnostics = PenDiagnosticCollector()
            defer { StandardError.write(diagnostics) }
            try await PenFileTransaction.read(at: url, diagnostics: diagnostics, fonts: .shared) { document in
                do {
                    let rendered = instances
                        ? try text(forInstancesIn: document)
                        : try text(for: NodeLookup.find(node, in: document, expanding: expand))
                    print(rendered)
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
            }
        }
    }

    // MARK: - Output

    /// The bytes the verb prints: the wrapped report, or the header line and the node.
    ///
    /// - Parameter found: The node and its revision.
    /// - Returns: The whole of stdout, without a trailing newline.
    /// - Throws: Whatever the JSON encoder throws.
    private func text(for found: NodeLookup.Result) throws -> String {
        guard !output.json else {
            return try CanonicalJSON.text(found.report)
        }
        let header = "\(found.address)  \(found.path)  rev \(found.revision)"
        let json = try CanonicalJSON.text(found.node)
        let props = ParameterListFormatter.text(found.parameters)
        return [header, props, json].compactMap(\.self).joined(separator: "\n")
    }

    /// The bytes `--instances` prints: the definition's header line and one row per
    /// `ref` that draws it.
    ///
    /// - Parameter document: The document to read.
    /// - Returns: The whole of stdout, without a trailing newline.
    /// - Throws: ``CommandFailure`` when the address names something no `ref` can
    ///   point at, or whatever the address resolution and the JSON encoder throw.
    private func text(forInstancesIn document: EditableDocument) throws -> String {
        let report = try InstanceLookup.find(node, in: document)
        return try output.json
            ? InstanceReportFormatter.json(report)
            : InstanceReportFormatter.text(report)
    }
}
