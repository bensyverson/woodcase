//
//  BatchPoison.swift
//  Woodcase
//

import Foundation

/// What a batch has already lost, so later lines can be skipped instead of tried.
///
/// A batch applies what it can, which only works if "this line could never have
/// worked" is distinguishable from "this line is wrong". This is that
/// distinction: every line that fails or cascades leaves behind the tag it
/// would have defined, the addresses it would have made resolvable, and the
/// ids it was acting on. A later line naming any of them is
/// ``BatchLineStatus/cascaded``.
///
/// Nothing here is exposed: it is the applier's bookkeeping, and the outcome a
/// caller sees is the status on ``BatchLineResult``.
struct BatchPoison {
    /// Tags declared by lines that did not apply.
    private var tags: Set<String> = []

    /// Addresses that name something a line that did not apply was acting on,
    /// or would have created.
    private var addresses: Set<String> = []

    /// Ids of nodes that lines which did not apply were targeting.
    private var ids: Set<String> = []

    /// Records what a line took down with it when it failed or cascaded.
    ///
    /// - Parameters:
    ///   - operation: The line that did not apply.
    ///   - document: The document it ran against, for resolving its target.
    ///   - knownTags: The tag map at the time, for resolving `@tag` addresses.
    mutating func absorb(
        _ operation: BatchOperation,
        in document: EditableDocument,
        tags knownTags: [String: String]
    ) {
        if let tag = operation.declaredTag {
            tags.insert(tag)
        }
        if let target = operation.targetAddress {
            addresses.insert(target.description)
            if let resolved = try? document.resolve(target, tags: knownTags) {
                ids.insert(resolved.targetID)
            }
        }
        for address in wouldHaveCreated(operation, in: document, tags: knownTags) {
            addresses.insert(address)
        }
    }

    /// Why a line cannot be attempted, or `nil` when it still can be.
    ///
    /// - Parameters:
    ///   - operation: The line about to run.
    ///   - document: The document it would run against.
    ///   - knownTags: The tag map at the time.
    /// - Returns: A sentence for ``BatchLineResult/error``, or `nil`.
    func cascadeReason(
        for operation: BatchOperation,
        in document: EditableDocument,
        tags knownTags: [String: String]
    ) -> String? {
        for address in operation.addresses {
            if case let .tag(name, _) = address, tags.contains(name) {
                return "skipped: @\(name) was never created, because the line that would have created it failed"
            }
            if let poisoned = poisonedPrefix(of: address.description) {
                return "skipped: \(poisoned) was left unusable by an earlier line that failed"
            }
            if let resolved = try? document.resolve(address, tags: knownTags), ids.contains(resolved.targetID) {
                return "skipped: \(document.namePath(of: resolved)) was the target of an earlier line that failed"
            }
        }
        return nil
    }

    /// The poisoned address a written address names, or lives under.
    private func poisonedPrefix(of written: String) -> String? {
        addresses.first { written == $0 || written.hasPrefix("\($0)\(NodeAddress.separator)") }
    }

    /// The addresses a creating line would have made resolvable, had it applied.
    ///
    /// A node is addressable by its name alone from any ancestor, and by its
    /// full path under the parent it was going for, so both are poisoned. An
    /// unnamed node makes no address, which is exactly why the applier refuses
    /// to create one.
    private func wouldHaveCreated(
        _ operation: BatchOperation,
        in document: EditableDocument,
        tags knownTags: [String: String]
    ) -> [String] {
        let name: String?
        let parent: NodeAddress?
        switch operation {
        case let .add(op):
            name = op.node.common.name
            parent = op.parent
        case let .cp(op):
            let source = try? document.resolve(op.source, tags: knownTags)
            name = source.flatMap { document.node(id: $0.targetID)?.common.name }
            parent = op.parent
        case .set, .replace, .mv, .rm, .override, .variable, .themeAxis, .importOp:
            // A replace creates nodes, but only beneath an address it already names
            // as its target — which ``absorb(_:in:tags:)`` poisons, prefix and all.
            return []
        }

        guard let name, !name.isEmpty else { return [] }
        guard let parent else { return [name] }
        return [name, "\(parent.description)\(NodeAddress.separator)\(name)"]
    }
}
