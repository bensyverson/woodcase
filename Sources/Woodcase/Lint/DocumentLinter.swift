//
//  DocumentLinter.swift
//  Woodcase
//

import Foundation

/// The checks a .pen document can fail, run over the layout as it settles.
///
/// A lint is a read: it opens nothing, writes nothing, and reports what a renderer
/// would do rather than what the file says. Every geometric check therefore runs on
/// ``TreeView``'s own rows — the same settled rects and the same clip flag `tree`
/// prints — so the two reads can never disagree about a node, and every sizing
/// question goes to `PenLayoutEngine.widthSizing(of:)`, so "what does
/// `fill_container` mean here" has one answer and the layout owns it.
///
/// ```swift
/// let findings = try DocumentLinter.findings(in: document)
/// print(LintFormatter.text(findings))
/// // warning clipped  Card/Title (x9Kqp)  20,80 160×24 sits partly outside Card (200×100)
/// ```
///
/// ## What it checks
///
/// The ``LintCheck`` cases, and nothing else. Seven come from the settled tree — text
/// with no fill, text in a box too short for it (see ``textOverflow(_:node:)``), text
/// whose settled width or height is zero (see ``collapsedText(_:node:)``), a
/// `fill_container` node whose parent sizes to content on the same axis, a
/// `fit_content` container with no children, a `layout: none` frame with children that
/// settles at 0 on an axis (see ``collapsedAbsoluteFrame(_:node:)``), a node outside its
/// parent — one
/// from the settled canvas — two roots on top of each other, see
/// ``artboardOverlaps(rows:in:)`` — one from the listing itself — two siblings sharing
/// a name, see ``duplicateNames(rows:)`` — seven from the document itself — a `ref` with
/// no component, a property still holding a `$variable`, an `icon` node's library not
/// one ``PenIconFontRegistry`` knows, an `icon` name not in its library's table (see
/// `DocumentLinter+Icons.swift`), a `ref`'s stored override carrying a value, a key or
/// a property the instance will drop on expansion (see `DocumentLinter+Overrides.swift`)
/// — three from what Pen does to a file it opens: a mesh gradient it paints nothing for
/// or paints distorted (see `DocumentLinter+MeshGradient.swift`), and a text stroke,
/// underline or strikethrough it strips (see `DocumentLinter+TextStripped.swift`)
/// — three from the metadata `generate react` reads: a `_props` entry that resolves to
/// no descendant, a `_role` outside ``ComponentRole``, and an instance whose overrides no
/// declared prop covers (see `DocumentLinter+Codegen*.swift`) — and one,
/// ``LintCheck/pipeline``, is whatever diagnostics the caller hands in.
///
/// ## What it does not check
///
/// **Fonts.** Whether a font family is a typo or a Google font waiting to be
/// downloaded cannot be decided offline, so a lint never asks. A caller that has run
/// ``GoogleFontResolver/prepareFonts(for:diagnostics:)`` passes the collector's
/// diagnostics in as `diagnostics:` and they arrive as ``LintCheck/pipeline`` findings.
///
/// **Instances.** The walk does not expand component instances: a component is linted
/// once, where it is defined, rather than once per instance. A fault an override
/// introduces in one instance alone is therefore not reported — with two exceptions.
/// An instance's own `rootOverrides` and `descendants` are read for unresolved
/// variables, against the same variable table the expansion resolves them with: a
/// `$name` mistyped into an override is a finding at the instance, and a defined one
/// is not. The same `descendants` map is also read for a value, a key or a property the
/// instance's own expansion will drop silently — see `DocumentLinter+Overrides.swift`.
public enum DocumentLinter {
    /// Lints a document — or one subtree of it — for a chosen theme.
    ///
    /// - Parameters:
    ///   - document: The document to lint.
    ///   - root: The address of the subtree to lint, in any form
    ///     ``EditableDocument/resolve(_:tags:)-(String,_)`` accepts. `nil` lints every
    ///     root node. Note that the subtree's own root has no parent *in this listing*,
    ///     so it is never reported as clipped — exactly as `tree` shows it.
    ///   - theme: Theme axes to pin for variable resolution, merged over the document's
    ///     default theme. `nil` uses the default theme.
    ///   - diagnostics: Diagnostics the caller collected from the pipeline. Each becomes
    ///     a ``LintCheck/pipeline`` finding, keeping the diagnostic's own severity, at
    ///     the node it names. One naming a node outside the scope is dropped, and so is
    ///     a document-level one when `root` scopes the lint to a subtree.
    /// - Returns: The findings, in document order: document-level ones first, then one
    ///   node at a time in pre-order.
    /// - Throws: ``EditingError/addressNotFound(address:nearMisses:)`` or
    ///   ``EditingError/ambiguousAddress(address:candidates:)`` when `root` names no
    ///   single node. An address that matches nothing is an error, never a clean bill
    ///   of health.
    public static func findings(
        in document: EditableDocument,
        root: String? = nil,
        theme: [String: String]? = nil,
        diagnostics: [PenDiagnostic] = []
    ) throws -> [LintFinding] {
        try findings(
            in: document,
            settled: SettledTree(document: document, theme: theme ?? [:]),
            theme: theme ?? [:],
            root: root,
            diagnostics: diagnostics
        )
    }

    /// Lints a document that has already been settled.
    ///
    /// The only difference from ``findings(in:root:theme:diagnostics:)`` is who runs
    /// the pipeline — the same split ``TreeView/rows(of:settled:root:depth:expandInstances:properties:)``
    /// makes, and for the same reason. `WoodcaseScripting` keeps one settled tree per
    /// theme for the length of a script run, so `doc.tree()` and `doc.lint()` in the
    /// same script settle the document once between them rather than twice each.
    ///
    /// - Parameters:
    ///   - document: The document the settled tree describes.
    ///   - settled: The already-settled tree, built for `theme`.
    ///   - theme: The theme axes `settled` was built with. Passing a different set here
    ///     would report findings against geometry nobody asked for, so the two travel
    ///     together.
    ///   - root: The address of the subtree to lint, or `nil` for the whole document.
    ///   - diagnostics: Diagnostics the caller collected from the pipeline.
    /// - Returns: The findings, in document order.
    /// - Throws: ``EditingError/addressNotFound(address:nearMisses:)`` or
    ///   ``EditingError/ambiguousAddress(address:candidates:)`` when `root` names no
    ///   single node.
    package static func findings(
        in document: EditableDocument,
        settled: SettledTree,
        theme: [String: String],
        root: String? = nil,
        diagnostics: [PenDiagnostic] = []
    ) throws -> [LintFinding] {
        let rows = try TreeView.rows(of: document, settled: settled, root: root)
        let context = Context(document: document, settled: settled, theme: theme)

        var index: [String: Int] = [:]
        for (position, row) in rows.enumerated() where index[row.id] == nil {
            index[row.id] = position
        }

        var perRow: [Int: [PenDiagnostic]] = [:]
        var found: [LintFinding] = root == nil ? importFindings(in: document) : []
        for diagnostic in diagnostics {
            guard let nodeID = diagnostic.nodeID else {
                if root == nil { found.append(finding(for: diagnostic, at: nil)) }
                continue
            }
            if let position = index[nodeID] {
                perRow[position, default: []].append(diagnostic)
            }
        }

        let overlaps = artboardOverlaps(rows: rows, in: document)
        let duplicates = duplicateNames(rows: rows)
        let clips = clippedFindings(rows: rows, in: context)
        let roles = codegenRoleFindings(rows: rows, in: context)

        var ancestors: [TreeRow] = []
        for (position, row) in rows.enumerated() {
            while let last = ancestors.last, last.depth >= row.depth {
                ancestors.removeLast()
            }
            found += (perRow[position] ?? []).map { finding(for: $0, at: row) }
            found += findings(for: row, parent: ancestors.last, in: context)
            found += overlaps[row.id] ?? []
            found += duplicates[row.id] ?? []
            found += clips[row.id] ?? []
            found += roles[row.id] ?? []
            ancestors.append(row)
        }
        return found
    }

    // MARK: - The walk

    /// Everything a check needs that does not change from node to node.
    ///
    /// Not `private`: ``DocumentLinter/clippedFindings(rows:in:)`` in
    /// `DocumentLinter+Scroll.swift` needs ``resolved(_:)`` to read a clipping
    /// frame's own `clip` flag and `_scroll` metadata, the same way every other
    /// check reads a settled node.
    struct Context {
        let document: EditableDocument
        let settled: SettledTree

        /// Every node with its variables resolved for the theme but its refs left
        /// standing, keyed by authored id.
        ///
        /// The settled tree resolves variables *after* expansion, so a `ref` — which
        /// expansion replaces with the component's root — never meets the variable
        /// table, and its `rootOverrides` and `descendants` still read `"$name"`
        /// however well defined the name is. This second, unexpanded resolve is the
        /// same pipeline stage applied to the ref where it is authored, so the
        /// overrides here hold exactly what the expansion patches into the component.
        private let unexpanded: [String: PenNode]

        /// Every reusable node in the document, rebuilt with its children, keyed by id.
        ///
        /// The flat store strips a node's children on the way in, and so does
        /// ``unexpanded``, so neither can answer "what is under this component" — which
        /// is the whole question the three codegen checks ask. This is the same registry
        /// ``EditableDocument/materializedComponents()`` hands the ref expander, so a
        /// definition the lint walks is the definition the pipeline expands, and it is
        /// also the tree ``ComponentAnalyzer`` reads: `generate react` analyzes the
        /// materialized document.
        let components: [String: PenNode]

        init(document: EditableDocument, settled: SettledTree, theme: [String: String]) {
            self.document = document
            self.settled = settled
            unexpanded = SettledTree.indexed(
                PenVariableResolver.resolve(document.materializeWithImports(), theme: theme).children
            )
            components = document.materializedComponents()
        }

        /// The node as the file stores it: the flat-store node behind a row.
        func authored(_ row: TreeRow) -> PenNode? {
            node(for: row, in: document.nodes)
        }

        /// The node as it renders: after ref expansion and variable resolution, falling
        /// back for a `ref` to the same node resolved without expansion, and to the
        /// authored node for anything the tree walk reaches but the pipeline does not.
        func resolved(_ row: TreeRow) -> PenNode? {
            settled.nodes[row.id] ?? node(for: row, in: unexpanded) ?? authored(row)
        }

        /// A row's node in one index, by its own id or — inside an instance — by the
        /// last step of its id path.
        private func node(for row: TreeRow, in index: [String: PenNode]) -> PenNode? {
            if let node = index[row.id] { return node }
            guard let last = row.id.split(separator: NodeAddress.separator).last else { return nil }
            return index[String(last)]
        }
    }

    /// Every finding for one row, in a fixed order so the output is stable.
    private static func findings(
        for row: TreeRow,
        parent: TreeRow?,
        in context: Context
    ) -> [LintFinding] {
        guard let node = context.resolved(row) else { return [] }
        var found: [LintFinding] = []
        found += brokenRef(row, node: node, in: context)
        found += unresolvedVariables(row, node: node)
        found += overrideFindings(row, node: node, in: context)
        found += textWithoutFill(row, node: node)
        found += textOverflow(row, node: node)
        found += collapsedText(row, node: node)
        found += textStyleStripped(row, node: node)
        found += fillContainerInFitParent(row, node: node, parent: parent, in: context)
        found += emptyFitContent(row, node: node)
        found += collapsedAbsoluteFrame(row, node: node)
        found += iconFindings(row, node: node)
        found += meshGradientFindings(row, node: node)
        found += shaderFindings(row, node: node)
        found += perSideStrokeOnShape(row, node: node)
        found += codegenPropPathFindings(row, node: node, in: context)
        found += codegenUnmappedOverrideFindings(row, node: node, in: context)
        return found
    }

    // MARK: - Checks

    /// A `ref` whose component id is in no registry entry — the document's own, or the
    /// one its imports contribute.
    private static func brokenRef(_ row: TreeRow, node: PenNode, in context: Context) -> [LintFinding] {
        guard case let .ref(data) = node.kind,
              context.document.reusableComponent(data.ref) == nil
        else { return [] }
        return [finding(.brokenRef, row, brokenRefMessage(for: data.ref, in: context.document))]
    }

    /// Any `$name` still standing in the node after variable resolution.
    private static func unresolvedVariables(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        variableReferences(in: node).sorted().map { name in
            finding(
                .unresolvedVariable, row,
                "still refers to `$\(name)` after variable resolution: no variable of that name "
                    + "is defined for this theme."
            )
        }
    }

    /// A text node with no fill at all.
    private static func textWithoutFill(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard case let .text(data) = node.kind, data.fills?.all.isEmpty ?? true else { return [] }
        return [finding(
            .textWithoutFill, row,
            "declares no fill, so it draws nothing: Pen renders text without a fill invisible, "
                + "and so does Woodcase. Give it a fill to show it."
        )]
    }

    /// A `fill_container` axis whose parent sizes to content on the same axis.
    ///
    /// The parent cannot know its own size until its children are measured, and the
    /// child is measured with nothing available to fill, so the child collapses. A
    /// fallback (`fill_container(200)`) is what the engine falls back to, so a child
    /// that has one is left alone.
    private static func fillContainerInFitParent(
        _ row: TreeRow,
        node: PenNode,
        parent: TreeRow?,
        in context: Context
    ) -> [LintFinding] {
        guard let parent, let parentNode = context.resolved(parent) else { return [] }
        var axes: [String] = []
        if collapsingFill(PenLayoutEngine.widthSizing(of: node)),
           PenLayoutEngine.widthSizing(of: parentNode).isFitContent
        {
            axes.append("width")
        }
        if collapsingFill(PenLayoutEngine.heightSizing(of: node)),
           PenLayoutEngine.heightSizing(of: parentNode).isFitContent
        {
            axes.append("height")
        }
        guard !axes.isEmpty else { return [] }
        return [finding(
            .fillContainerInFitParent, row,
            "is fill_container on \(list(axes)), but \(name(of: parent)) sizes to content there, "
                + "so it sizes without this node, which gets Pen's 1pt floor and overflows it. "
                + "Size the parent, or give this one a fallback — "
                + "`fill_container(200)`."
        )]
    }

    /// A container that sizes to content on an axis and has no content.
    ///
    /// A **slot** frame is exempt. A slot is the hole a component leaves for its
    /// instances to fill — its children come from each instance's `children` override,
    /// not from the definition — so it is empty exactly as designed, and reporting it
    /// is the check firing at the feature. That sentence is what taught writers a
    /// component with a hole in it was a mistake.
    private static func emptyFitContent(_ row: TreeRow, node: PenNode) -> [LintFinding] {
        guard isContainer(node.kind), row.childCount == 0, !row.isSlot else { return [] }
        var axes: [String] = []
        if bareFitContent(PenLayoutEngine.widthSizing(of: node)) { axes.append("width") }
        if bareFitContent(PenLayoutEngine.heightSizing(of: node)) { axes.append("height") }
        guard !axes.isEmpty else { return [] }
        return [finding(
            .emptyFitContent, row,
            "sizes to content on \(list(axes)) but has no children, so it resolves to 0. "
                + "Give it a size, or a fallback — `fit_content(200)`."
        )]
    }

    /// A row `tree` flags as clipped, worded the way every clipped row was worded
    /// before a declared or stacking scroll axis could exempt one.
    ///
    /// The flag is ``TreeRow/clip``, computed once by the tree read; this check reads
    /// it rather than deciding for itself, which is what keeps `lint` and `tree` from
    /// disagreeing about the same node. Not `private`: it is the fallback
    /// ``DocumentLinter/clippedFindings(rows:in:)`` (`DocumentLinter+Scroll.swift`)
    /// reaches for whenever a row's overflow is not the parent's declared or
    /// stacking scroll axis.
    static func clipped(_ row: TreeRow, parent: TreeRow?) -> [LintFinding] {
        guard let parent, let rect = row.rect, row.clip != .none else { return [] }
        let how = row.clip == .partial ? "partly" : "entirely"
        let box = parent.rect.map { " (\(number($0.width))×\(number($0.height)))" } ?? ""
        let consequence = row.clip == .partial
            ? " Part of it is cut off if the parent clips."
            : " None of it is visible."
        return [finding(
            .clipped, row,
            "\(describe(rect)) sits \(how) outside \(name(of: parent))\(box).\(consequence)"
        )]
    }

    // MARK: - Findings

    /// A finding about one row.
    ///
    /// Not `private`: the three codegen checks
    /// (`DocumentLinter+Codegen*.swift`) report against a row exactly like every check
    /// here, and a second copy of this two-line initializer in each of them is how a
    /// finding's `path` starts disagreeing with a row's address.
    static func finding(_ check: LintCheck, _ row: TreeRow, _ message: String) -> LintFinding {
        LintFinding(check: check, nodeID: row.id, path: row.address, message: message)
    }

    /// A pipeline diagnostic as a finding, keeping the diagnostic's severity and
    /// naming the stage it came from.
    private static func finding(for diagnostic: PenDiagnostic, at row: TreeRow?) -> LintFinding {
        LintFinding(
            check: .pipeline,
            severity: diagnostic.severity,
            nodeID: row?.id,
            path: row?.address,
            message: "[\(diagnostic.stage.rawValue)] \(diagnostic.message)"
        )
    }

    // MARK: - Reading nodes

    /// Every variable name a node still refers to.
    ///
    /// Read from the node's own encoding rather than field by field: a `$name` survives
    /// resolution as ``PenValue/variable(_:)``, ``PenSizing/variable(_:)`` or a raw
    /// string in an override map, and all three encode back to `"$name"`. The node's
    /// identity keys are skipped — an id or a name is not a reference, whatever it
    /// starts with.
    private static func variableReferences(in node: PenNode) -> Set<String> {
        guard let data = try? JSONEncoder().encode(node),
              let object = try? JSONSerialization.jsonObject(with: data)
        else { return [] }
        var names: Set<String> = []
        collectReferences(object, into: &names)
        return names
    }

    /// The keys that are never variable references, whatever they hold.
    private static let identityKeys: Set<String> = ["id", "name", "type", "ref", "href"]

    /// Walks an encoded node collecting `$name` strings.
    private static func collectReferences(_ value: Any, into names: inout Set<String>) {
        switch value {
        case let dictionary as [String: Any]:
            for (key, inner) in dictionary where !identityKeys.contains(key) {
                collectReferences(inner, into: &names)
            }
        case let array as [Any]:
            for inner in array {
                collectReferences(inner, into: &names)
            }
        case let text as String:
            if text.hasPrefix("$"), text.count > 1 {
                names.insert(String(text.dropFirst()))
            }
        default:
            break
        }
    }

    /// Whether a kind holds children, so "no children" is a thing to say about it.
    private static func isContainer(_ kind: PenNode.Kind) -> Bool {
        switch kind {
        case .frame, .group: true
        default: false
        }
    }

    /// Whether a sizing fills its parent with no fallback to fall back on.
    private static func collapsingFill(_ sizing: PenSizing) -> Bool {
        if case let .fillContainer(fallback) = sizing { return fallback == nil }
        return false
    }

    /// Whether a sizing fits its content with no fallback to fall back on.
    private static func bareFitContent(_ sizing: PenSizing) -> Bool {
        if case let .fitContent(fallback) = sizing { return fallback == nil }
        return false
    }

    // MARK: - Words and numbers

    /// A row named the way a reader recognizes it: its name, or its id marker.
    ///
    /// Not `private`: ``DocumentLinter/clippedFindings(rows:in:)`` in
    /// `DocumentLinter+Scroll.swift` names the clipping frame the same way.
    static func name(of row: TreeRow) -> String {
        row.name ?? NodeAddress.marker(forID: row.id)
    }

    /// `"width"`, or `"width and height"`.
    private static func list(_ axes: [String]) -> String {
        axes.joined(separator: " and ")
    }

    /// A rect as `x,y w×h`, matching what a tree row prints.
    private static func describe(_ rect: PenRect) -> String {
        "\(number(rect.x)),\(number(rect.y)) \(number(rect.width))×\(number(rect.height))"
    }

    /// A number with no decimal point when it is integral, and two places when it is not.
    ///
    /// Not `private`: ``DocumentLinter/clippedFindings(rows:in:)`` in
    /// `DocumentLinter+Scroll.swift` prints the same way how far past the fold a
    /// collapsed group of children continues.
    static func number(_ value: Double) -> String {
        guard value.isFinite else { return value.isNaN ? "nan" : (value > 0 ? "inf" : "-inf") }
        guard value.rounded() == value, abs(value) < 1e15 else { return String(format: "%.2f", value) }
        return String(Int64(value))
    }
}
