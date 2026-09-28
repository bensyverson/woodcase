//
//  InstanceReport.swift
//  WoodcaseCommandCore
//

import Foundation
import Woodcase

/// The `--json` shape of `woodcase get <definition> --instances`: the component, and
/// every `ref` that draws it.
///
/// The definition and its instances are described by the same three fields, because
/// the question a caller asks next is the same for both: address it, and write to it
/// quoting its revision. Every ``Row/rev`` is
/// ``Woodcase/EditableDocument/revision(of:)`` for that node, so an agent that reads
/// the list and then overrides one instance already holds the pin that write needs —
/// and the definition's own `rev` moves whenever any instance's rendering does.
///
/// This is the one struct both the producer and any consumer decode, so the wire shape
/// cannot drift. ``Woodcase/NodeReport`` is its sibling for a plain `woodcase get`.
struct InstanceReport: Friendly {
    /// One node in the listing: the definition, or one instance of it.
    struct Row: Friendly {
        /// Creates a row.
        ///
        /// - Parameters:
        ///   - id: The node's id.
        ///   - address: The node's full name path.
        ///   - rev: The node's revision.
        init(id: String, address: String, rev: String) {
            self.id = id
            self.address = address
            self.rev = rev
        }

        /// The node's id — the address every verb accepts, whatever it is named.
        let id: String

        /// The node's full name path, which resolves back to this same node.
        let address: String

        /// The revision a write against this node must quote back.
        let rev: String
    }

    /// Creates a report.
    ///
    /// - Parameters:
    ///   - definition: The reusable component the instances point at.
    ///   - instances: Every `ref` targeting it, in document order.
    init(definition: Row, instances: [Row]) {
        self.definition = definition
        self.instances = instances
    }

    /// The reusable component the listing is about.
    let definition: Row

    /// Every `ref` whose target is that component, in document order. Empty when
    /// nothing points at it — which is an answer, not a failure.
    let instances: [Row]
}
