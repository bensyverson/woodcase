//
//  RandomEditGenerator+Components.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// Keeps the merge set from writing a component that renders itself.
///
/// A component holding an instance of itself, directly or through other components,
/// makes ``EditableDocument/revision(of:)`` exponential: a fold that meets a component
/// already on its chain is not memoized, nor is anything above it. Real files do not do
/// this, and a fuzz run that does spends minutes hashing instead of merging.
extension RandomEditGenerator {
    /// Whether putting the subtree holding `refs` under `parentID` would make some
    /// component render itself.
    ///
    /// - Parameters:
    ///   - refs: The components the moved or inserted subtree has instances of.
    ///   - parentID: Where the subtree goes; `nil` for the top level.
    ///   - doc: The document as it stands.
    func closesComponentCycle(adding refs: Set<String>, under parentID: String?, in doc: EditableDocument) -> Bool {
        var enclosing: [String] = []
        var cursor = parentID
        while let id = cursor {
            if doc.componentRegistry[id] != nil { enclosing.append(id) }
            cursor = doc.parents[id]
        }
        return enclosing.contains { component in refs.contains { reaches($0, component, in: doc) } }
    }

    /// The components a subtree has instances of.
    func instanceTargets(under rootID: String, in doc: EditableDocument) -> Set<String> {
        Set(doc.descendantIDs(of: rootID).compactMap { id -> String? in
            guard case let .ref(data)? = doc.nodes[id]?.kind else { return nil }
            return data.ref
        })
    }

    /// Whether component `from` renders `to`, itself or through the components it uses.
    private func reaches(_ from: String, _ to: String, in doc: EditableDocument) -> Bool {
        var seen: Set<String> = []
        var pending = [from]
        while let id = pending.popLast() {
            if id == to { return true }
            guard seen.insert(id).inserted, doc.nodes[id] != nil else { continue }
            pending.append(contentsOf: instanceTargets(under: id, in: doc))
        }
        return false
    }
}
