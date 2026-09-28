//
//  SwiftUIShapeDeclarations.swift
//  Woodcase
//

/// The `Shape` types one page declares for its paths, polygons, lines and arcs, each
/// named for its node and written below the page's view.
///
/// A shared reference, like the diagnostics collector, because the node emitter is a
/// value copied into every call: each node's shape is declared once, the first time any
/// step asks for it — its fill, its stroke or its shadow — and found again by node id.
final class SwiftUIShapeDeclarations {
    /// One declared type: its name and its source lines, unindented.
    struct Declaration: Friendly {
        /// The type's name, `ZigZagShape`.
        var name: String

        /// The declaration's source lines.
        var lines: [String]
    }

    /// The declarations, in the order they were made.
    private(set) var declarations: [Declaration] = []

    private var namesByNode: [String: String] = [:]
    /// Names in use; the support file's shape types are taken from the start.
    private var taken: Set<String> = ["PenIconShape"]

    /// The type already declared for the node `nodeID`, if any.
    func name(forNode nodeID: String) -> String? {
        namesByNode[nodeID]
    }

    /// Declares a shape for the node `nodeID` labelled `label`, named for the label and
    /// made unique on the page; `lines` receives the name and returns the declaration.
    func declare(nodeID: String, label: String, _ lines: (String) -> [String]) -> String {
        if let name = namesByNode[nodeID] { return name }
        let base = Self.identifier(label) + "Shape"
        var name = base
        var suffix = 2
        while taken.contains(name) {
            name = "\(base)\(suffix)"
            suffix += 1
        }
        taken.insert(name)
        namesByNode[nodeID] = name
        declarations.append(Declaration(name: name, lines: lines(name)))
        return name
    }

    /// `label` as an upper-camel-case Swift identifier: its runs of letters and digits,
    /// each capitalised, prefixed `Node` when that is empty or starts with a digit.
    static func identifier(_ label: String) -> String {
        let words = label.split { !($0.isLetter || $0.isNumber) || !$0.isASCII }
        let joined = words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined()
        guard let first = joined.first, !first.isNumber else { return "Node" + joined }
        return joined
    }
}
