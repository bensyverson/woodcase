//
//  NodeDetails.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Everything the Details tab knows about the selected node: what it is, and one
/// ``NodeDetail`` per property it actually carries.
///
/// ## Three documents, because there are three answers
///
/// The pane reads the node from the document **as it renders** — expanded, so a node
/// inside a component instance exists at all — but it needs the *authored* value to say
/// where that value came from, and those are not the same document:
///
/// | Document | Answers |
/// |---|---|
/// | the editable store | which node an address means, and what the definition says |
/// | expanded, variables unresolved | what was written here — `$accent`, or a literal |
/// | expanded, variables resolved | what it is worth under the theme on screen |
///
/// Reading only the resolved document would report every `$accent` as the hex it
/// happens to be today; reading only the authored one would report a variable and never
/// say what it means. So both are read, and the row carries both facts.
///
/// The property vocabulary is ``NodePropertyCodec``'s — the same codec paths `woodcase
/// get` prints and `woodcase set` accepts — so a row is a property you can go and
/// change, spelled the way the command wants it.
public struct NodeDetails: Friendly, Identifiable {
    /// Creates a set of details.
    ///
    /// - Parameters:
    ///   - id: The node's id in the expanded document, which is what the layout, the
    ///     render overlay and `?node=` all address it by.
    ///   - address: The id-form address that resolves back to this node.
    ///   - path: The node's name path.
    ///   - name: The node's name, or `nil` when it has none.
    ///   - type: The node's type, as the format spells it.
    ///   - revision: The revision a write against this node must quote.
    ///   - instance: The instance this node sits inside, when it sits inside one.
    ///   - rows: One row per property the node carries, in codec-path order.
    public init(
        id: String,
        address: String,
        path: String,
        name: String?,
        type: String,
        revision: String,
        instance: String?,
        rows: [NodeDetail]
    ) {
        self.id = id
        self.address = address
        self.path = path
        self.name = name
        self.type = type
        self.revision = revision
        self.instance = instance
        self.rows = rows
    }

    /// The node's id in the expanded document.
    public let id: String

    /// The id-form address that resolves back to this node.
    public let address: String

    /// The node's name path.
    public let path: String

    /// The node's name, or `nil` when it has none.
    public let name: String?

    /// The node's type, as the format spells it.
    public let type: String

    /// The revision a write against this node must quote.
    public let revision: String

    /// The instance this node sits inside — the `ref` whose overrides reach it.
    public let instance: String?

    /// One row per property the node carries, in codec-path order.
    public let rows: [NodeDetail]

    /// What a person calls this node.
    public var label: String {
        name ?? "#\(id)"
    }

    // MARK: - Building

    /// Reads one node's details out of the three documents that know about it.
    ///
    /// - Parameters:
    ///   - address: The `?node=` value — an id, a name path, or an instance path.
    ///   - document: The editable store, for addressing and for the definition a node
    ///     inside an instance was cloned from.
    ///   - expanded: The expanded document with variables still written as `$name`.
    ///   - resolved: The same document with variables resolved for the theme on screen.
    /// - Returns: The details.
    /// - Throws: ``Woodcase/EditingError`` when the address names no single node — the
    ///   pane never answers an unknown address with an empty list of rows.
    public static func of(
        address: String,
        in document: EditableDocument,
        expanded: PenDocument,
        resolved: PenDocument
    ) throws -> NodeDetails {
        let target = try document.resolve(address)
        let id = document.expandedID(of: target)
        guard let node = first(in: expanded.children, id: id) else {
            throw EditingError.addressNotFound(address: id, nearMisses: [])
        }
        let rendered = first(in: resolved.children, id: id) ?? node
        let definition = definition(of: id, in: document)
        let instance = instance(of: target, in: document)

        return NodeDetails(
            id: id,
            address: target.address,
            path: document.namePath(of: target),
            name: node.common.name,
            type: node.kind.typeName,
            revision: document.revision(of: target.targetID) ?? document.documentRevision,
            instance: instance,
            rows: rows(
                of: node,
                rendered: rendered,
                definition: definition,
                instance: instance.map {
                    (id: $0, path: document.namePath(of: $0))
                }
            )
        )
    }

    /// One row per property the node carries, skipping the ones it leaves unset.
    ///
    /// Unset is not a value: ``NodePropertyCodec/paths(for:)`` lists the whole
    /// vocabulary of the node's kind, and a text node that sets two of twenty-odd
    /// properties should read as two rows, not as eighteen em-dashes.
    ///
    /// - Parameters:
    ///   - node: The node as authored — expanded, variables unresolved.
    ///   - rendered: The same node with variables resolved.
    ///   - definition: The component node this one was cloned from, when it was.
    ///   - instance: The instance an override would be stored on, and its name path.
    /// - Returns: The rows, in codec-path order.
    static func rows(
        of node: PenNode,
        rendered: PenNode,
        definition: PenNode?,
        instance: (id: String, path: String)?
    ) -> [NodeDetail] {
        let keys = wireKeys(of: node)
        return NodePropertyCodec.paths(for: node).compactMap { path in
            guard let authored = try? NodePropertyCodec.value(at: path, of: node),
                  authored != .null
            else { return nil }

            let names = variableNames(in: authored)
            let was = definition.flatMap { try? NodePropertyCodec.value(at: path, of: $0) }
            let source = source(for: authored, was: was, instance: instance)

            return NodeDetail(
                path: path,
                key: keys[path] ?? field(of: path),
                value: ViewerVariable.describe(
                    (try? NodePropertyCodec.value(at: path, of: rendered)) ?? authored
                ),
                origin: source != nil ? .override : (names.isEmpty ? .literal : .variable),
                variables: names,
                source: source
            )
        }
    }

    /// The instance a value departs from its definition by, when it does.
    ///
    /// - Parameters:
    ///   - authored: The value on the expanded node.
    ///   - was: The definition's value, or `nil` when there is no definition to compare
    ///     against or the property is not one the definition's kind carries.
    ///   - instance: The instance the override would be stored on.
    /// - Returns: The source, or `nil` when the value is the definition's own.
    static func source(
        for authored: AnyCodable,
        was: AnyCodable?,
        instance: (id: String, path: String)?
    ) -> NodeDetail.Source? {
        guard let instance, let was, was != authored else { return nil }
        return NodeDetail.Source(
            instance: instance.id,
            path: instance.path,
            was: ViewerVariable.describe(was)
        )
    }

    /// The key each codec path is written under in the file, from the schema the
    /// decoders generate — never a second name table written out by hand.
    ///
    /// - Parameter node: The node whose kind decides the `kind.*` half.
    /// - Returns: Codec path to wire key.
    static func wireKeys(of node: PenNode) -> [String: String] {
        var keys: [String: String] = [:]
        for property in PenSchema.common.properties {
            keys[property.path] = property.key.written
        }
        guard let type = PenSchema.type(named: node.kind.typeName) else { return keys }
        for property in PenSchema.table(for: type).properties {
            keys[property.path] = property.key.written
        }
        return keys
    }

    // MARK: - Pieces

    /// The variables an authored value names, sorted and deduplicated.
    ///
    /// A reference is a string beginning with `$` — the resolver's own test — and it can
    /// be anywhere in the value, not only at the top of it: a fill object holds its
    /// colour under a key, and an effect array holds one per entry.
    ///
    /// - Parameter value: The authored value.
    /// - Returns: The names, without their `$`.
    static func variableNames(in value: AnyCodable) -> [String] {
        var found: Set<String> = []
        collectVariables(value, into: &found)
        return found.sorted()
    }

    /// Walks a value adding every `$name` it finds.
    private static func collectVariables(_ value: AnyCodable, into found: inout Set<String>) {
        switch value {
        case let .string(text) where text.hasPrefix("$") && text.count > 1:
            found.insert(String(text.dropFirst()))
        case let .array(items):
            for item in items {
                collectVariables(item, into: &found)
            }
        case let .dictionary(pairs):
            for item in pairs.values {
                collectVariables(item, into: &found)
            }
        default:
            break
        }
    }

    /// The stored node an expanded node was cloned from.
    ///
    /// Expansion prefixes every id in a clone with the instance's own, at every level,
    /// so the last segment of an expanded id is the component node's own id — and that
    /// node is still in the flat store, because expansion never touches the definition.
    /// An id with no separator is a node that was never cloned.
    ///
    /// - Parameters:
    ///   - id: The expanded id.
    ///   - document: The store to look the definition up in.
    /// - Returns: The definition node, or `nil` when this node is not part of a clone.
    static func definition(of id: String, in document: EditableDocument) -> PenNode? {
        guard let last = id.split(separator: NodeAddress.separator).last.map(String.init),
              last != id
        else { return nil }
        return document.node(id: last)
    }

    /// The instance an override to this target would be written on.
    ///
    /// For a node inside an instance that is ``ResolvedNodeAddress/targetID`` — the
    /// *outermost* `ref`, which is where the format stores the override, even when the
    /// node lives inside a nested instance two levels down. For the instance root
    /// itself it is the `ref` node the address named.
    ///
    /// - Parameters:
    ///   - target: What the address resolved to.
    ///   - document: The store, to tell a `ref` from a plain node.
    /// - Returns: The instance's id, or `nil` when this node is not part of one.
    static func instance(of target: ResolvedNodeAddress, in document: EditableDocument) -> String? {
        switch target {
        case let .instanceDescendant(refID, _):
            refID
        case let .node(id):
            if case .ref = document.node(id: id)?.kind { id } else { nil }
        }
    }

    /// The field name inside a codec path — `kind.fills` is `fills`.
    private static func field(of path: String) -> String {
        String(path.drop(while: { $0 != "." }).dropFirst())
    }

    /// The first node with an id, in document order.
    private static func first(in nodes: [PenNode], id: String) -> PenNode? {
        for node in nodes {
            if node.id == id { return node }
            if let hit = first(in: node.kind.inlineChildren, id: id) { return hit }
        }
        return nil
    }
}
