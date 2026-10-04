//
//  ChangeInvalidation+Probe.swift
//  Woodcase
//

import Foundation

extension ChangeInvalidation {
    /// What one operation's invalidation needs to know from the document before it
    /// applies, finished against the document after.
    ///
    /// Some of an invalidation is only visible beforehand — the parent a node is moved or
    /// deleted out of, a deleted subtree, a node's properties before a write — and some
    /// only afterwards — where a node landed. A probe is taken first, the operation is
    /// applied, and ``invalidation(after:)`` reads the rest.
    struct Probe {
        /// Reads what the operation is about to change.
        ///
        /// - Parameters:
        ///   - operation: The normalized operation about to be applied.
        ///   - keys: Its ``ChangeKey/keys(of:in:)``, computed against the same document.
        ///   - document: The document, before the operation.
        init(operation: EditOperation, keys: [ChangeKey], in document: EditableDocument) {
            self.operation = operation
            placed = Set(keys.compactMap(Self.placedNode))
            var nodes = Set(document.subjects(of: operation))
            nodes.formUnion(keys.compactMap(Self.node))
            nodes.formUnion(placed.compactMap { document.parents[$0] })
            nodesBefore = nodes
            atRootBefore = !placed.isDisjoint(with: document.rootOrder)
            nodeBefore = Self.writtenNode(of: operation).flatMap { document.nodes[$0] }
            tablesBefore = Self.declaredTables(of: document)
        }

        /// The operation being applied.
        let operation: EditOperation

        /// The nodes whose place or existence the operation changes.
        let placed: Set<String>

        /// The nodes the invalidation names, as far as the document before can tell.
        let nodesBefore: Set<String>

        /// Whether a placed node was a top-level node before.
        let atRootBefore: Bool

        /// The node a property write changes, as it was.
        let nodeBefore: PenNode?

        /// The document tables declared before.
        let tablesBefore: Set<DocumentChangeKey.Table>

        /// The operation's invalidation, finished against the document it was applied to.
        ///
        /// - Parameter document: The document, after the operation.
        /// - Returns: What the operation can have changed.
        func invalidation(after document: EditableDocument) -> ChangeInvalidation {
            var nodes = nodesBefore
            nodes.formUnion(placed.compactMap { document.parents[$0] })
            var result = Self.classify(operation)
            result.nodes = nodes
            if result.category == nil, let nodeBefore, let nodeAfter = document.nodes[nodeBefore.id] {
                result.category = ChangeCategory.merge(
                    ChangeCategory.categorize(oldCommon: nodeBefore.common, newCommon: nodeAfter.common),
                    ChangeCategory.categorize(oldKind: nodeBefore.kind, newKind: nodeAfter.kind)
                )
            }
            if atRootBefore || !placed.isDisjoint(with: document.rootOrder) {
                result.documentLevel.insert(.rootOrder)
            }
            let tables = Self.declaredTables(of: document).symmetricDifference(tablesBefore)
            result.documentLevel.formUnion(tables.map(DocumentChangeKey.declaredTable))
            return result
        }

        /// The category, flags and document-level keys an operation implies by its case
        /// alone. A property write's category depends on what changed, so it is left
        /// `nil` here for ``invalidation(after:)`` to fill in.
        private static func classify(_ operation: EditOperation) -> ChangeInvalidation {
            switch operation {
            case .insertNode, .deleteNode, .moveNode, .replaceSubtree, .detachRef:
                ChangeInvalidation(category: .structural, structural: true)
            case .updateCommon, .updateKind, .setProperties:
                ChangeInvalidation()
            case .overrideDescendant, .overrideRoot:
                ChangeInvalidation(category: .layout)
            case let .addVariable(op):
                ChangeInvalidation(category: .structural, documentLevel: [.variable(op.name)], full: true)
            case let .updateVariable(op):
                ChangeInvalidation(category: .structural, documentLevel: [.variable(op.name)], full: true)
            case let .removeVariable(op):
                ChangeInvalidation(category: .structural, documentLevel: [.variable(op.name)], full: true)
            case let .addImport(op):
                ChangeInvalidation(category: .structural, documentLevel: [.importAlias(op.alias)], full: true)
            case let .updateImport(op):
                ChangeInvalidation(category: .structural, documentLevel: [.importAlias(op.alias)], full: true)
            case let .removeImport(op):
                ChangeInvalidation(category: .structural, documentLevel: [.importAlias(op.alias)], full: true)
            case let .addThemeAxis(op):
                ChangeInvalidation(category: .structural, documentLevel: [.themeAxis(op.name)], full: true)
            case let .updateThemeAxis(op):
                ChangeInvalidation(category: .structural, documentLevel: [.themeAxis(op.name)], full: true)
            case let .removeThemeAxis(op):
                ChangeInvalidation(category: .structural, documentLevel: [.themeAxis(op.name)], full: true)
            case let .setDocumentProperties(op):
                documentProperties(Array(op.properties.keys))
            }
        }

        /// A root patch's keys: fonts re-measure every text node; the version, the file
        /// token and the root's unmodeled keys change no rendering.
        private static func documentProperties(_ keys: [String]) -> ChangeInvalidation {
            var result = ChangeInvalidation()
            for key in keys {
                switch key {
                case DocumentPropertyCodec.fontsKey:
                    result.documentLevel.insert(.fonts)
                    result.category = .layout
                    result.full = true
                case DocumentPropertyCodec.versionKey:
                    result.documentLevel.insert(.version)
                case DocumentPropertyCodec.fileTokenKey:
                    result.documentLevel.insert(.fileToken)
                default:
                    result.documentLevel.insert(.extra(String(key.dropFirst(DocumentPropertyCodec.extrasPrefix.count))))
                }
            }
            return result
        }

        /// The node a key belongs to, if any.
        private static func node(of key: ChangeKey) -> String? {
            switch key {
            case let .property(node, _), let .placement(node), let .existence(node): node
            case let .override(ref, _, _), let .rootOverride(ref, _): ref
            case .variable, .importAlias, .themeAxis, .document: nil
            }
        }

        /// The node whose place or existence a key names, if any.
        private static func placedNode(of key: ChangeKey) -> String? {
            switch key {
            case let .placement(node), let .existence(node): node
            default: nil
            }
        }

        /// The node a property write changes, if the operation is one.
        private static func writtenNode(of operation: EditOperation) -> String? {
            switch operation {
            case let .updateCommon(op): op.nodeID
            case let .updateKind(op): op.nodeID
            case let .setProperties(op): op.nodeID
            default: nil
            }
        }

        /// The keyed tables a document declares, written empty or not.
        private static func declaredTables(of document: EditableDocument) -> Set<DocumentChangeKey.Table> {
            var tables: Set<DocumentChangeKey.Table> = []
            if document.variables != nil { tables.insert(.variables) }
            if document.imports != nil { tables.insert(.imports) }
            if document.themes != nil { tables.insert(.themes) }
            return tables
        }
    }
}
