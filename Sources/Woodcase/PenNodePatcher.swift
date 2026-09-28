//
//  PenNodePatcher.swift
//  Woodcase
//

import Foundation

/// Shared override-application logic used by both ``PenRefExpander`` (at parse time)
/// and ``ReactEmitter`` (at code-gen time for inline ref expansion).
public enum PenNodePatcher {
    /// The raw .pen key a container's subtree is stored under.
    public static let childrenKey = "children"

    /// The raw .pen key naming the component a `ref` node places; an override that
    /// sets it repoints a nested instance.
    public static let refKey = "ref"

    /// The keys a patch may name that are not properties of the node's kind.
    ///
    /// ``patched(_:with:)`` merges a patch onto the node's own JSON object, so a key
    /// survives exactly when the node's type decodes it — and `children` is such a key
    /// on a container without being a property any schema lists. That is what lets an
    /// instance fill a component's slot frame: the `children` it writes into its
    /// `descendants` map replace the frame's own, and the expansion draws them.
    ///
    /// Anything judging an override — "will anything ever read this key?" — asks here
    /// rather than keeping a list of its own, because a second list is exactly what
    /// told writers a slot fill would never be read while this patcher was applying it.
    ///
    /// - Parameter node: The node the patch will be merged onto.
    /// - Returns: ``childrenKey`` for a kind that carries children, and nothing for one
    ///   that does not.
    public static func structuralKeys(of node: PenNode) -> Set<String> {
        node.kind.canHaveChildren ? [childrenKey] : []
    }

    /// Applies descendant overrides to matching nodes in the tree.
    ///
    /// The walk does not enter children an override itself writes — a slot fill, or a
    /// whole-node replacement's subtree. Those are the instance's own slot content, and
    /// Pen does not let the same instance's keys reach them: it drops such a key
    /// (`project/2026-09-26-slot-override-keys.md`, rule 5). The walk does not recurse,
    /// so its stack use does not grow with the tree.
    ///
    /// - Parameters:
    ///   - node: The tree to patch.
    ///   - overrides: Node id → override.
    ///   - enteringRoot: Whether the walk enters the root's children; `false` when they
    ///     are the instance's own, written on its `ref` node.
    /// - Returns: The patched tree.
    public static func applyOverrides(
        to node: PenNode,
        overrides: [String: PenDescendantOverride],
        enteringRoot: Bool = true
    ) -> PenNode {
        guard !overrides.isEmpty else { return node }
        return PenTreeRewrite.rewrite(node, context: true) { current, isRoot in
            let override = overrides[current.id]
            let patched = override.map { applyOverride(to: current, override: $0) } ?? current
            let sealed = override?.writesChildren == true || (isRoot && !enteringRoot)
            return sealed ? .keep(patched) : .descend(patched, false)
        } ?? node
    }

    /// Applies a single override to a node.
    public static func applyOverride(
        to node: PenNode,
        override: PenDescendantOverride
    ) -> PenNode {
        if override.isObjectReplacement {
            replaceNode(original: node, override: override) ?? node
        } else {
            patchNode(node, with: override.properties)
        }
    }

    /// Patches individual properties onto an existing node using JSON merge.
    ///
    /// The merge is defined on the node's own JSON object: a patch names keys, and only
    /// those keys change. A node's `children` therefore survive untouched unless the
    /// patch names `children` itself — so when it does not, they are lifted off before
    /// the merge and put back after, and the subtree is never read.
    ///
    /// That shortcut is the difference between a patch costing the node and a patch
    /// costing everything beneath it. Component overrides are applied at the *root* of
    /// an instance, so the slow path re-serialized a whole screen to change one name:
    /// ref expansion was 492 ms of the 715 ms `tree woodcase-app.pen` took, and that is
    /// where nearly all of it went. See <doc:WoodcasePerformance>.
    ///
    /// The merged object is never written out, either: ``PenNodeOverlay`` decodes the
    /// node from its own captured values with the patch laid over them, which is the
    /// same merge without the four coder passes a literal JSON round trip costs — see
    /// ``Route``.
    ///
    /// Expansion is tolerant on purpose: Woodcase renders files it did not write, and a
    /// file Pen itself accepts must still draw. The refusal belongs at the *write* —
    /// ``EditableDocument`` checks an override's values with ``patched(_:with:)`` before
    /// storing them, so an override written through Woodcase either applies or is
    /// refused, and only a hand-made one can reach the silent fallback here.
    ///
    /// - Parameters:
    ///   - node: The node to patch.
    ///   - patchProperties: The keys to merge over the node's own JSON object.
    /// - Returns: The patched node, or `node` unchanged if the merge cannot be decoded.
    public static func patchNode(
        _ node: PenNode,
        with patchProperties: [String: AnyCodable]
    ) -> PenNode {
        (try? patched(node, with: patchProperties)) ?? node
    }

    /// The same patch as ``patchNode(_:with:)``, raising the failure it swallows.
    ///
    /// A patch whose value the node's type cannot decode makes the whole merge fail, and
    /// the patcher's answer to that is the *unpatched* node — an override that reads back
    /// from the `descendants` map forever and never changes a pixel. A caller deciding
    /// whether to *store* such a patch needs the failure itself, and the `DecodingError`
    /// is also what says which part of a structured value was refused.
    ///
    /// - Parameters:
    ///   - node: The node to patch.
    ///   - patchProperties: The keys to merge over the node's own JSON object.
    /// - Returns: The patched node.
    /// - Throws: The `DecodingError` the merged JSON object raised.
    public static func patched(
        _ node: PenNode,
        with patchProperties: [String: AnyCodable]
    ) throws -> PenNode {
        // A patch that renames the node's `type` reads every value it keeps as another
        // type's, which only the round trip can do.
        guard patchProperties[PenDescendantOverride.typeKey] == nil else {
            return try merge(node, with: patchProperties)
        }
        switch route {
        case .jsonRoundTrip:
            return try withoutChildren(of: node, unlessNamedBy: patchProperties) { try merge($0, with: patchProperties) }
        case .overlayOnly:
            return try withoutChildren(of: node, unlessNamedBy: patchProperties) {
                try PenNodeOverlay.merged($0, with: patchProperties)
            }
        case .overlay:
            do {
                return try withoutChildren(of: node, unlessNamedBy: patchProperties) {
                    try PenNodeOverlay.merged($0, with: patchProperties)
                }
            } catch {
                // Declined, or refused: the round trip either answers what the overlay
                // could not read back, or raises the refusal in `JSONDecoder`'s words,
                // which the writers that report it quote.
                return try withoutChildren(of: node, unlessNamedBy: patchProperties) {
                    try merge($0, with: patchProperties)
                }
            }
        }
    }

    // MARK: - Private

    /// Runs a merge with the node's children lifted off and put back after, unless the
    /// patch names `children` itself or the node has none to lift.
    ///
    /// - Parameters:
    ///   - node: The node to patch.
    ///   - patchProperties: The patch, read only for `children`.
    ///   - merge: The merge to run on the childless node.
    /// - Returns: The merged node, its children restored.
    /// - Throws: Whatever `merge` throws.
    private static func withoutChildren(
        of node: PenNode,
        unlessNamedBy patchProperties: [String: AnyCodable],
        _ merge: (PenNode) throws -> PenNode
    ) throws -> PenNode {
        guard patchProperties[childrenKey] == nil, let children = detachedChildren(of: node.kind) else {
            return try merge(node)
        }
        var childless = node
        childless.kind = replacingChildren(nil, in: node.kind)
        var merged = try merge(childless)
        merged.kind = replacingChildren(children, in: merged.kind)
        return merged
    }

    /// The JSON merge itself, over whatever subtree the node still carries.
    ///
    /// A node that will not encode has nothing to judge the patch against, so it comes
    /// back unchanged rather than as a failure the caller would blame on the patch.
    ///
    /// - Parameters:
    ///   - node: The node to encode, merge and decode.
    ///   - patchProperties: The keys to merge; a patch key wins over the node's own.
    /// - Returns: The merged node, or `node` when the node itself will not encode.
    /// - Throws: The `DecodingError` the merged JSON object raised.
    private static func merge(
        _ node: PenNode,
        with patchProperties: [String: AnyCodable]
    ) throws -> PenNode {
        guard let nodeData = try? JSONEncoder().encode(node),
              var nodeDict = try? JSONDecoder().decode([String: AnyCodable].self, from: nodeData)
        else {
            return node
        }

        for (key, value) in patchProperties {
            nodeDict[key] = value
        }

        return try JSONDecoder().decode(PenNode.self, from: JSONEncoder().encode(nodeDict))
    }

    /// The children a kind carries, or `nil` when it carries none to lift off.
    ///
    /// `nil` covers both a kind that cannot have children and a container whose
    /// `children` is absent — in either case there is nothing to save, so the caller
    /// takes the ordinary path rather than reasoning about an empty array that was
    /// never there.
    ///
    /// - Parameter kind: The kind to read.
    /// - Returns: The children, or `nil`.
    private static func detachedChildren(of kind: PenNode.Kind) -> [PenNode]? {
        switch kind {
        case let .frame(data): data.children
        case let .group(data): data.children
        default: nil
        }
    }

    /// A kind with its `children` set to `children`, for the kinds that have any.
    ///
    /// - Parameters:
    ///   - children: The children to set, or `nil` to clear them.
    ///   - kind: The kind to rewrite.
    /// - Returns: The rewritten kind, or `kind` unchanged when it holds no children.
    private static func replacingChildren(
        _ children: [PenNode]?,
        in kind: PenNode.Kind
    ) -> PenNode.Kind {
        switch kind {
        case let .frame(data):
            var updated = data
            updated.children = children
            return .frame(updated)
        case let .group(data):
            var updated = data
            updated.children = children
            return .group(updated)
        default:
            return kind
        }
    }

    /// Replaces a node entirely using the override's properties (which include a `type` field).
    private static func replaceNode(
        original: PenNode,
        override: PenDescendantOverride
    ) -> PenNode? {
        var dict = override.properties
        dict["id"] = .string(original.id)
        return decoded(PenNode.self, from: .dictionary(dict))
    }
}
