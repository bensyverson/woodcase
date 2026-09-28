//
//  TreeCommand.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Foundation
import Woodcase

/// Prints the settled structure of a .pen file: one row per node.
///
/// This is the read verb to run first, and the cheap answer a screenshot is usually
/// standing in for. Every rect is computed by the layout engine after component
/// expansion and variable resolution, so a read taken straight after a write reports
/// what the file actually renders, never an authored size.
struct Tree: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Read: the settled node tree of a .pen file, one row per node.",
        discussion: """
        A read verb: it takes a shared lock, writes nothing, and leaves the file's \
        bytes and modification date alone.

        The header line carries the document's revision — quote it back with --rev on \
        the write that follows and a document that changed underneath fails loudly \
        instead of being edited blind. Each row is the node's type, its name indented \
        by depth, the settled rect as `x,y w×h`, a clip flag when the node leaves its \
        parent, and its id. A `*` marks a reusable component definition and `+N` \
        counts children the listing left out.

        --json carries a per-node `rev` on every row: a content hash of everything that \
        node renders — what the file stores under it, and, through each component \
        instance, the definition it draws — so one frame's rev pins its whole subtree. \
        That is the narrower token to quote on --rev or --guard; the document revision \
        moves under any writer, a subtree's does not. Editing a component definition \
        moves the definition's rev and every instance's, because every instance now \
        draws something else.

        COORDINATES are parent-relative: a row's `x,y` is its offset inside its own \
        parent, and only a top-level node's rect is in canvas coordinates. --absolute \
        prints the same column in document space instead, from the same walk `shot \
        --outline` draws with, so two nodes in different parents can be compared \
        without adding up their ancestors. --json needs no flag: every row carries \
        `rect` and `absRect` both.

        --expand walks into component instances, listing each node under the id \
        path the expansion gives it, and that includes the children an instance \
        injects into a slot frame — a filled slot reads as filled. Those injected \
        ids name the nodes but are not yet addresses any verb resolves: change what \
        a slot holds by writing its `children` override again, whole.

        The last column of a row is an address every other verb accepts. Property \
        paths are the same ones `set` writes, prefixed `common.` or `kind.`, and \
        --props takes a comma-separated list of them. Written bare, --props widens \
        the listing with the columns most files carry.

          woodcase tree design.pen Dashboard --depth 2 --props kind.fill

        """
    )

    @Argument(help: "The .pen file to read.")
    var file: PenFilePath

    @Argument(help: "The subtree to list — an id, a name path, or an instance path. Omit for the whole file.")
    var node: String?

    @Option(name: .long, help: "How many levels below the root to descend. 0 lists the roots alone.")
    var depth: Int?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Property paths to show as columns, comma separated, e.g. \"kind.fill,common.name\". "
                + "Bare --props shows \(Tree.defaultPropertyPaths.joined(separator: ", "))."
        )
    )
    var props: String?

    @OptionGroup var themePin: ThemeOption

    @Flag(name: .long, help: "Walk into component instances, addressing their nodes by id path.")
    var expand: Bool = false

    @Flag(
        name: .long,
        help: ArgumentHelp(
            "Print rects in document space rather than relative to each node's parent. "
                + "--json carries both without it."
        )
    )
    var absolute: Bool = false

    @OptionGroup var output: OutputOptions

    /// Reads the file and prints the outline, or the JSON report.
    func run() async throws {
        let url = try file.existingFile()
        let pins = try ThemePinParser.parse(themePin.theme)
        let properties = Tree.propertyPaths(in: props)
        if let depth, depth < 0 {
            throw ValidationError("--depth must be 0 or more; \(depth) descends nothing.")
        }

        try await runReportingFailures(editing: url) {
            let diagnostics = PenDiagnosticCollector()
            defer { StandardError.write(diagnostics) }
            try await PenFileTransaction.read(at: url, diagnostics: diagnostics, fonts: .shared) { document in
                do {
                    let rows = try TreeView.rows(
                        of: document,
                        root: node,
                        depth: depth,
                        expandInstances: expand,
                        theme: pins,
                        properties: properties
                    )
                    let text = try render(rows, revision: document.documentRevision, properties: properties)
                    print(text)
                    PropertyColumnWarning.warnAboutEmptyColumns(properties, in: rows, expand: expand)
                } catch {
                    throw CommandFailure.describing(error, in: document, editing: url)
                }
            }
        }
    }

    // MARK: - Output

    /// The bytes the verb prints: the JSON report, or the header line and the outline.
    ///
    /// - Parameters:
    ///   - rows: The rows to render.
    ///   - revision: The document's revision, for the header or the report.
    ///   - properties: The property columns that were asked for.
    /// - Returns: The whole of stdout, without a trailing newline.
    /// - Throws: Whatever the JSON encoder throws.
    private func render(_ rows: [TreeRow], revision: String, properties: [String]) throws -> String {
        guard !output.json else {
            return try TreeFormatter.json(rows, revision: revision)
        }
        // The header says which coordinate system the rect column is in, because a
        // saved outline outlives the command line that produced it and the two forms
        // are indistinguishable on a top-level node.
        let header = "rev \(revision)  \(rows.count) \(rows.count == 1 ? "row" : "rows")"
            + (absolute ? "  absolute" : "")
        let outline = TreeFormatter.text(rows, properties: properties, absolute: absolute)
        return outline.isEmpty ? header : "\(header)\n\(outline)"
    }

    /// The columns a bare `--props` widens the listing with.
    ///
    /// The four properties an authored file carries most of, once the columns a row
    /// already has — type, name, rect, id — are set aside: what shapes a container's
    /// children, what it is painted with, what it says, and how big the words are.
    /// Counted over the mobile-viewer kit with
    /// `python3 -c` over its 307 nodes (`project/2026-08-31-mobile-viewer/mobile-viewer.pen`):
    /// fill 163, layout 98, content 74, fontSize 74.
    static let defaultPropertyPaths = ["kind.layout", "kind.fill", "kind.content", "kind.fontSize"]

    /// Splits a `--props` value into property paths.
    ///
    /// A flag written but left empty — `--props`, filled in by ``BareOptionValue``, or
    /// `--props=` — names no columns in particular, so it gets ``defaultPropertyPaths``.
    /// Every other read defaults sensibly, and a flag whose only answer to being written
    /// bare is `Missing value for '--props <props>'` teaches nothing.
    ///
    /// - Parameter value: The flag's value, or `nil` when it was not given.
    /// - Returns: The paths, trimmed, in the order written, with empties dropped; the
    ///   defaults for an empty value, and none at all when the flag was absent.
    static func propertyPaths(in value: String?) -> [String] {
        guard let value else { return [] }
        let paths = value
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        return paths.isEmpty ? defaultPropertyPaths : paths
    }
}
