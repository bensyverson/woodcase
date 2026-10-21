//
//  FigmaImportError.swift
//  Woodcase
//

/// Why ``FigmaImporter`` refused a Figma message. A refusal is whole: the importer never
/// returns part of a selection.
public enum FigmaImportError: Error, Friendly, CustomStringConvertible {
    /// A selected node whose type the importer does not map.
    public struct UnsupportedNode: Friendly {
        /// The Figma node type, as the schema names it (`STICKY`, `STAR`).
        public var type: String
        /// The layer's name, if it had one.
        public var name: String?
        /// The id the node would have had.
        public var nodeID: String

        /// A node of `type` named `name`.
        public init(type: String, name: String?, nodeID: String) {
            self.type = type
            self.name = name
            self.nodeID = nodeID
        }
    }

    /// The selection holds nodes of types the importer does not map, each named here.
    case unsupportedNodes([UnsupportedNode])
    /// An instance's component is not in the clipboard, and the options say to refuse.
    case missingComponent(UnsupportedNode)
    /// The message has no node on a page to import.
    case noContent
    /// The message is not shaped as a Figma `NODE_CHANGES` message is.
    case malformedMessage(String)
    /// A geometry blob a node names could not be read.
    case blob(FigmaBlobError)

    /// One paragraph for a person, naming what was refused.
    public var description: String {
        switch self {
        case let .unsupportedNodes(nodes):
            let list = nodes.map { node in
                node.name.map { "\"\($0)\" (\(node.type))" } ?? node.type
            }.joined(separator: ", ")
            return "The selection holds Figma layers Penumbra cannot import yet: \(list). Nothing was imported."
        case let .missingComponent(node):
            return "\"\(node.name ?? node.nodeID)\" is an instance of a component the clipboard does not carry."
        case .noContent:
            return "The Figma clipboard holds no layers to import."
        case let .malformedMessage(reason):
            return "The Figma clipboard is not shaped as expected: \(reason)."
        case let .blob(error):
            return "A Figma geometry blob could not be read: \(error)."
        }
    }
}
