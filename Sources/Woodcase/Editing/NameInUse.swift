//
//  NameInUse.swift
//  Woodcase
//

import Foundation

/// A name the document still refers to, and the sentence that refuses removing it.
///
/// Four callers ask the same question — `woodcase vars rm`, `doc.vars.rm`,
/// `woodcase imports rm` and `doc.imports.rm` — and it is a question about
/// *consequence*, not about the format: ``EditableDocument`` removes a variable or an
/// import alias happily, and nothing fails afterwards. A node whose fill is `$brand`
/// renders the unresolved reference; a `ref` into a namespace that is no longer
/// imported resolves to nothing. Both are silent breakage, which is worth refusing, so
/// the refusal is a decision one type makes rather than a sentence four call sites
/// spell out.
///
/// ```swift
/// let inUse = NameInUse.variable("brand", in: document)
/// if !inUse.isEmpty, !force {
///     throw CommandFailure(message: inUse.sentence(in: .command(file: path)), exitCode: .usage)
/// }
/// ```
///
/// Only the remedy differs between callers, and that is what ``RemedyDialect`` is for:
/// `--force` at a shell prompt, `{ force: true }` inside a script.
public struct NameInUse: Friendly {
    /// Records what refers to a name.
    ///
    /// - Parameters:
    ///   - name: The name that would be removed — a variable's, or an import alias.
    ///   - nodePaths: The name paths of the nodes that refer to it, in document order.
    ///   - variableNames: The variables that resolve through it, sorted by name.
    public init(name: String, nodePaths: [String] = [], variableNames: [String] = []) {
        self.name = name
        self.nodePaths = nodePaths
        self.variableNames = variableNames
    }

    /// The name that would be removed — a variable's, or an import alias.
    public let name: String

    /// The name paths of the nodes that refer to it, in document order.
    public let nodePaths: [String]

    /// The variables that resolve through it, sorted by name.
    public let variableNames: [String]

    /// Whether nothing in the document refers to the name, so removing it is free.
    public var isEmpty: Bool {
        nodePaths.isEmpty && variableNames.isEmpty
    }

    /// How many distinct things refer to the name.
    public var count: Int {
        nodePaths.count + variableNames.count
    }

    /// The sentence a refused removal prints: what refers to the name, and the remedy.
    ///
    /// - Parameter dialect: Which grammar the remedy is written in — ``RemedyDialect``.
    /// - Returns: The message. Meaningless for a name nothing refers to, which is why
    ///   every caller checks ``isEmpty`` first.
    public func sentence(in dialect: RemedyDialect) -> String {
        var clauses: [String] = []
        if !nodePaths.isEmpty {
            let count = nodePaths.count
            clauses.append(
                "\(count) node\(count == 1 ? "" : "s") reference\(count == 1 ? "s" : "") it — "
                    + Self.list(nodePaths)
            )
        }
        if !variableNames.isEmpty {
            let count = variableNames.count
            clauses.append(
                "\(count) variable\(count == 1 ? "" : "s") resolve\(count == 1 ? "s" : "") "
                    + "through it — \(Self.list(variableNames))"
            )
        }
        return """
        Cannot remove \(name): \(clauses.joined(separator: ", and ")). Pass \
        \(Self.remedy(in: dialect)) to remove it anyway, leaving those references unresolved.
        """
    }

    // MARK: - Asking the document

    /// Everything that refers to one variable.
    ///
    /// - Parameters:
    ///   - name: The variable's name, without the `$`.
    ///   - document: The document to walk.
    /// - Returns: The nodes and variables that mention it, empty for a name nothing
    ///   mentions and for one the document does not define.
    public static func variable(_ name: String, in document: EditableDocument) -> NameInUse {
        let references = document.references(to: name)
        return NameInUse(
            name: name,
            nodePaths: references.nodeIDs.map(document.namePath(of:)),
            variableNames: references.variableNames
        )
    }

    /// Everything that reaches into one import's namespace.
    ///
    /// An import aliased `V` puts every identifier the library defines under a `V:`
    /// prefix — see <doc:PenImportNamespaces> — so what a removal would strand is every
    /// node holding one of those identifiers: a `ref` whose target is `V:Bt0aA`, a fill
    /// bound to `$V:--primary`, an override keyed by a library descendant. The walk
    /// therefore looks for the *namespace*, not for one field, and it sees whatever the
    /// format adds next for the same reason
    /// ``EditableDocument/variableReferences()`` does.
    ///
    /// - Parameters:
    ///   - alias: The import alias.
    ///   - document: The document to walk.
    /// - Returns: The nodes and variables that reach into the namespace, empty for an
    ///   alias nothing uses and for one the document does not import.
    /// - Complexity: O(*n*) in the encoded size of the document.
    public static func importAlias(_ alias: String, in document: EditableDocument) -> NameInUse {
        // The prefix `PenImportResolver` writes when it merges a library in.
        let prefix = "\(alias):"
        var nodePaths: [String] = []
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for nodeID in document.nodeIDsInDocumentOrder() {
            guard let node = document.nodes[nodeID] else { continue }
            if case let .ref(data) = node.kind, data.ref.hasPrefix(prefix) {
                nodePaths.append(document.namePath(of: nodeID))
                continue
            }
            guard let data = try? encoder.encode(node),
                  let json = try? decoder.decode(AnyCodable.self, from: data)
            else { continue }
            var mentioned: Set<String> = []
            EditableDocument.collectReferences(in: json, into: &mentioned)
            if mentioned.contains(where: { $0.hasPrefix(prefix) }) {
                nodePaths.append(document.namePath(of: nodeID))
            }
        }

        var variableNames: [String] = []
        for (owner, variable) in (document.variables ?? [:]).sorted(by: { $0.key < $1.key }) {
            var mentioned: Set<String> = []
            switch variable.value {
            case let .simple(value):
                EditableDocument.collectReferences(in: value, into: &mentioned)
            case let .themed(variants):
                for variant in variants {
                    EditableDocument.collectReferences(in: variant.value, into: &mentioned)
                }
            }
            if mentioned.contains(where: { $0.hasPrefix(prefix) }) {
                variableNames.append(owner)
            }
        }
        return NameInUse(name: alias, nodePaths: nodePaths, variableNames: variableNames)
    }

    // MARK: - Private

    /// The words a refusal offers as the way past it.
    private static func remedy(in dialect: RemedyDialect) -> String {
        switch dialect {
        case .command: "--force"
        case .batch, .script: "`{ force: true }`"
        }
    }

    /// Names, capped so a name used everywhere does not print a screenful.
    private static func list(_ names: [String]) -> String {
        let shown = names.prefix(listLimit).joined(separator: ", ")
        guard names.count > listLimit else { return shown }
        return "\(shown), and \(names.count - listLimit) more"
    }

    /// How many names a refusal spells out before counting the rest.
    private static let listLimit = 10
}
