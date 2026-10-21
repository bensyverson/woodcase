//
//  FigmaImporter.swift
//  Woodcase
//

/// Maps a decoded Figma clipboard message onto the Pen document model.
///
/// The result is a ``PenClip`` — the selected layers as roots at their canvas positions,
/// then any component an instance needs that was not selected — so a paste goes through
/// ``PenClip/plan(into:at:)`` as a Pen copy does, which re-ids, reuses components and
/// places the roots. Beside it come the ``FigmaImportLoss``es: everything the mapping could
/// not carry, field by field, so a caller can say what changed.
///
/// A selection holding a node type the importer does not map is refused whole
/// (``FigmaImportError/unsupportedNodes(_:)``), never imported in part. <doc:FigmaImport>
/// is the mapping table.
///
/// ```swift
/// let clipboard = try FigmaClipboardDecoder().decode(html: html)
/// let result = try FigmaImporter().clip(from: clipboard)
/// let plan = try result.clip.plan(into: document, at: target)
/// ```
public struct FigmaImporter: Friendly {
    /// The caller's choices.
    public var options: FigmaImportOptions

    /// An importer with `options`.
    public init(options: FigmaImportOptions = FigmaImportOptions()) {
        self.options = options
    }

    /// The selection a decoded clipboard carries, as a clip.
    ///
    /// - Throws: ``FigmaImportError`` when the selection holds a node the importer cannot
    ///   map, has nothing to import, or names a blob it cannot read.
    public func clip(from clipboard: FigmaClipboard) throws(FigmaImportError) -> FigmaImport {
        try clip(from: clipboard.message)
    }

    /// The selection a decoded `Message` carries, as a clip.
    ///
    /// - Throws: ``FigmaImportError`` when the selection holds a node the importer cannot
    ///   map, has nothing to import, or names a blob it cannot read.
    public func clip(from message: KiwiRecord) throws(FigmaImportError) -> FigmaImport {
        let tree = try FigmaNodeTree(message: message)
        guard !tree.roots.isEmpty else { throw .noContent }
        let (components, definitions) = Self.components(for: tree.roots, in: tree)
        try refuseUnsupported(tree.roots + definitions, in: tree, components: components)
        let blobs: FigmaBlobTable
        do { blobs = try FigmaBlobTable(message: message) } catch { throw .blob(error) }
        var session = FigmaImportSession(options: options, tree: tree, blobs: blobs, components: components)
        var content: [PenNode] = []
        for root in tree.roots {
            try content.append(session.node(root))
        }
        var carried: [PenNode] = []
        for definition in definitions {
            try carried.append(session.node(definition))
        }
        let document = PenDocument(children: content + carried)
        return FigmaImport(clip: PenClip(document: document, contentIDs: content.map(\.id)), losses: session.losses)
    }

    /// The Pen id of the Figma node with this GUID: `figma-<session>-<local>`.
    ///
    /// Stable for a node, so an instance's ref and its overrides can name a component and
    /// its children before either is mapped; a paste re-ids whatever collides.
    public static func penID(sessionID: UInt32, localID: UInt32) -> String {
        "figma-\(sessionID)-\(localID)"
    }

    /// Every component the clip carries, and those of them that were not selected, which
    /// travel as extra roots: each instance's component, followed through the components
    /// it in turn uses.
    static func components(for roots: [FigmaGUID], in tree: FigmaNodeTree) -> (all: Set<FigmaGUID>, definitions: [FigmaGUID]) {
        let content = roots.flatMap { tree.subtree($0) }
        var all = Set(content.filter { tree.type(of: $0) == "SYMBOL" })
        var definitions: [FigmaGUID] = []
        var wanted = content.compactMap { instanceComponent(of: $0, in: tree) }
        while let next = wanted.popLast() {
            guard !all.contains(next), tree.type(of: next) == "SYMBOL" else { continue }
            all.insert(next)
            definitions.append(next)
            let inner = tree.subtree(next)
            all.formUnion(inner.filter { tree.type(of: $0) == "SYMBOL" })
            wanted += inner.compactMap { instanceComponent(of: $0, in: tree) }
        }
        return (all, definitions)
    }

    /// The component an instance node names, or `nil` for any other node.
    private static func instanceComponent(of guid: FigmaGUID, in tree: FigmaNodeTree) -> FigmaGUID? {
        guard tree.type(of: guid) == "INSTANCE" else { return nil }
        return FigmaGUID(tree.records[guid]?["symbolData"]?["symbolID"])
    }

    /// Refuses the selection when any node under `roots` is of a type the importer does not
    /// map, naming every one; or, when the options say so, when an instance's component is
    /// not carried.
    private func refuseUnsupported(_ roots: [FigmaGUID], in tree: FigmaNodeTree, components: Set<FigmaGUID>) throws(FigmaImportError) {
        var unsupported: [FigmaImportError.UnsupportedNode] = []
        for guid in roots.flatMap({ tree.subtree($0) }) {
            let type = tree.type(of: guid)
            let node = FigmaImportError.UnsupportedNode(type: type, name: tree.records[guid]?["name"]?.stringValue, nodeID: guid.penID)
            if !FigmaImportSession.supportedTypes.contains(type) {
                unsupported.append(node)
            } else if options.missingComponents == .refuse, let component = Self.instanceComponent(of: guid, in: tree),
                      !components.contains(component)
            {
                throw .missingComponent(node)
            }
        }
        if !unsupported.isEmpty { throw .unsupportedNodes(unsupported) }
    }
}
