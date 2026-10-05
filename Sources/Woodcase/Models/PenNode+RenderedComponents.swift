//
//  PenNode+RenderedComponents.swift
//  Woodcase
//

import Foundation

extension PenNode {
    /// The component ids this node, on its own, could render: for a `ref`, the one it
    /// names, then every `ref` its overrides write, at any depth.
    ///
    /// An instance draws more than its authored component. It can repoint one of the
    /// component's nested refs by writing `ref` into its `descendants`, and it can fill a
    /// slot with a `children` list — plain values on the ref, not nodes of any store —
    /// whose instances draw their own components. So every override value is searched
    /// for an object whose `ref` is a string. A name that is no component is still
    /// listed; a caller that only wants components filters against its registry.
    ///
    /// The search runs from a work list: slot content can nest instances in instances.
    ///
    /// - Returns: The authored component first, the others sorted, none repeated. Empty
    ///   for anything but a `ref`.
    var renderedComponentIDs: [String] {
        guard case let .ref(refData) = kind else { return [] }
        var named: Set<String> = []
        var pending: [AnyCodable] = (refData.descendants ?? [:]).values.map { .dictionary($0.properties) }
        if let rootOverrides = refData.rootOverrides { pending.append(.dictionary(rootOverrides)) }
        while let value = pending.popLast() {
            switch value {
            case let .dictionary(fields):
                if case let .string(target)? = fields["ref"] { named.insert(target) }
                pending.append(contentsOf: fields.values)
            case let .array(items):
                pending.append(contentsOf: items)
            default:
                continue
            }
        }
        return [refData.ref] + named.subtracting([refData.ref]).sorted()
    }
}
