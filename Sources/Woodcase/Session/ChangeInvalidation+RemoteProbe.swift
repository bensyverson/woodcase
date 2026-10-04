//
//  ChangeInvalidation+RemoteProbe.swift
//  Woodcase
//

import Foundation

extension ChangeInvalidation {
    /// What a batch of a collaborator's operations can have changed, read by comparing
    /// the document before the batch with the document after it.
    ///
    /// A local edit's ``Probe`` reads the operation before applying it. A remote batch
    /// cannot be read that way: its ``DocumentMutation``s exist only once the CRDT has
    /// resolved each operation, and the reconciliation that closes the batch may
    /// reparent or reorder anywhere while naming no subjects. So this probe keeps the
    /// document's tables as they were — copy-on-write values, so keeping them costs
    /// nothing until the batch writes — and compares: every written node, every node
    /// whose parent changed together with both parents, every parent whose children
    /// changed, and the root order. The comparison is linear in the document, as the
    /// reconciliation it follows already is.
    struct RemoteProbe {
        /// Keeps what the batch may change.
        ///
        /// - Parameter document: The collaborative document, before the batch.
        init(_ document: EditableDocument) {
            nodesBefore = document.nodes
            parentsBefore = document.parents
            childrenBefore = document.children
            rootOrderBefore = document.rootOrder
            tablesBefore = Probe.declaredTables(of: document)
        }

        /// The nodes, as they were.
        let nodesBefore: [String: PenNode]

        /// Each node's parent, as it was.
        let parentsBefore: [String: String]

        /// Each parent's children, as they were.
        let childrenBefore: [String: [String]]

        /// The top-level nodes, as they were.
        let rootOrderBefore: [String]

        /// The document tables declared before.
        let tablesBefore: Set<DocumentChangeKey.Table>

        /// The batch's invalidation, finished against the document it left.
        ///
        /// - Parameters:
        ///   - mutations: Every mutation the batch wrote, in order.
        ///   - document: The document, after the batch and its reconciliation.
        /// - Returns: What the batch can have changed.
        func invalidation(of mutations: [DocumentMutation], after document: EditableDocument) -> ChangeInvalidation {
            var result = ChangeInvalidation()
            var written = Set<String>()
            for mutation in mutations {
                switch mutation {
                case let .setNode(node): written.insert(node.id)
                case let .removeNode(nodeID): written.insert(nodeID)
                case .setChildren, .setParent, .removeParent: break
                case let .setVariable(name, _), let .removeVariable(name): result.formUnion(Self.full(.variable(name)))
                case let .setImport(alias, _), let .removeImport(alias): result.formUnion(Self.full(.importAlias(alias)))
                case let .setThemeAxis(name, _), let .removeThemeAxis(name): result.formUnion(Self.full(.themeAxis(name)))
                }
            }
            for nodeID in written {
                result.formUnion(content(of: nodeID, after: document))
            }
            result.formUnion(placement(after: document))
            let tables = Probe.declaredTables(of: document).symmetricDifference(tablesBefore)
            result.documentLevel.formUnion(tables.map(DocumentChangeKey.declaredTable))
            return result
        }

        /// A written node's invalidation: its category when it was edited in place,
        /// structural when it arrived or left.
        private func content(of nodeID: String, after document: EditableDocument) -> ChangeInvalidation {
            guard let before = nodesBefore[nodeID], let after = document.nodes[nodeID] else {
                return ChangeInvalidation(nodes: [nodeID], category: .structural, structural: true)
            }
            let category = ChangeCategory.merge(
                ChangeCategory.categorize(oldCommon: before.common, newCommon: after.common),
                ChangeCategory.categorize(oldKind: before.kind, newKind: after.kind)
            )
            return ChangeInvalidation(nodes: [nodeID], category: category)
        }

        /// Every change of place: moved nodes with the parents they left and joined,
        /// reordered children lists, and the root order.
        private func placement(after document: EditableDocument) -> ChangeInvalidation {
            var nodes = Set<String>()
            for nodeID in Set(parentsBefore.keys).union(document.parents.keys)
                where parentsBefore[nodeID] != document.parents[nodeID]
            {
                nodes.insert(nodeID)
                nodes.formUnion([parentsBefore[nodeID], document.parents[nodeID]].compactMap(\.self))
            }
            for parentID in Set(childrenBefore.keys).union(document.children.keys)
                where childrenBefore[parentID] != document.children[parentID]
            {
                nodes.insert(parentID)
            }
            let rootChanged = rootOrderBefore != document.rootOrder
            guard !nodes.isEmpty || rootChanged else { return ChangeInvalidation() }
            return ChangeInvalidation(
                nodes: nodes,
                category: .structural,
                documentLevel: rootChanged ? [.rootOrder] : [],
                structural: true
            )
        }

        /// A document member any node can read changed, so everything may render
        /// differently.
        private static func full(_ key: DocumentChangeKey) -> ChangeInvalidation {
            ChangeInvalidation(category: .structural, documentLevel: [key], full: true)
        }
    }
}
