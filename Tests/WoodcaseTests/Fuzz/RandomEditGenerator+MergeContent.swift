//
//  RandomEditGenerator+MergeContent.swift
//  WoodcaseTests
//

import Foundation
@testable import Woodcase

/// The merge set's content operations: path-level patches, extras, retypes, child-list
/// declarations, instance overrides and the document root.
extension RandomEditGenerator {
    /// Sets or clears one or two properties of a random node by path.
    mutating func patchProperties(in _: EditableDocument, nodeIDs: [String], label: String, index: Int) -> EditOperation? {
        guard let nodeID = nodeIDs.randomElement(using: &rng) else { return nil }
        var properties: [String: AnyCodable] = [:]
        for _ in 0 ..< Int.random(in: 1 ... 2, using: &rng) {
            switch Int.random(in: 0 ..< 6, using: &rng) {
            case 0: properties["common.name"] = .string("\(label)\(index)")
            case 1: properties["common.opacity"] = Bool.random(using: &rng) ? .null : .double(Double(Int.random(in: 0 ... 10, using: &rng)) / 10)
            case 2: properties["common.x"] = Bool.random(using: &rng) ? .null : .int(Int.random(in: -50 ... 50, using: &rng))
            case 3: properties["kind.width"] = .int(Int.random(in: 1 ... 40, using: &rng) * 10)
            case 4: properties["kind.fills"] = .string(hexColor())
            default: properties["common.enabled"] = .bool(Bool.random(using: &rng))
            }
        }
        return .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: properties))
    }

    /// Sets or removes one of two node extras — keys a file wrote that no type models.
    mutating func patchExtra(in _: EditableDocument, nodeIDs: [String]) -> EditOperation? {
        guard let nodeID = nodeIDs.randomElement(using: &rng) else { return nil }
        let key = "extras.fuzz\(Int.random(in: 0 ..< 2, using: &rng))"
        let value: AnyCodable = Bool.random(using: &rng) ? .null : .int(Int.random(in: 0 ... 9, using: &rng))
        return .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: [key: value]))
    }

    /// Retypes a random node: to a leaf (refused while it holds children, so childless
    /// nodes are favored) or to a frame or group that declares an empty list, leaves it
    /// out, or keeps what it had.
    mutating func retype(in doc: EditableDocument, nodeIDs: [String]) -> EditOperation? {
        let childless = nodeIDs.filter { doc.children[$0]?.isEmpty ?? true }
        let pool = Bool.random(using: &rng) && !childless.isEmpty ? childless : nodeIDs
        guard let nodeID = pool.randomElement(using: &rng) else { return nil }
        switch Int.random(in: 0 ..< 4, using: &rng) {
        case 0, 1:
            return .updateKind(EditOperation.UpdateKind(nodeID: nodeID, kind: leafKind()))
        case 2:
            let kind = PenNode.Kind.frame(PenNode.FrameData(width: .fixed(Double(Int.random(in: 1 ... 40, using: &rng) * 10))))
            return .updateKind(EditOperation.UpdateKind(nodeID: nodeID, kind: kind, emptyChildren: emptyChildren()))
        default:
            return .updateKind(EditOperation.UpdateKind(nodeID: nodeID, kind: .group(PenNode.GroupData()), emptyChildren: emptyChildren()))
        }
    }

    /// Flips whether a random childless container writes `"children": []`, keeping its kind.
    mutating func redeclareChildren(in doc: EditableDocument, nodeIDs: [String]) -> EditOperation? {
        let empty = containers(in: doc, among: nodeIDs).filter { doc.children[$0]?.isEmpty ?? true }
        guard let nodeID = empty.randomElement(using: &rng), let node = doc.nodes[nodeID] else { return nil }
        let declaration: EditOperation.UpdateKind.EmptyChildren = doc.children[nodeID] == nil ? .declared : .absent
        return .updateKind(EditOperation.UpdateKind(nodeID: nodeID, kind: node.kind, emptyChildren: declaration))
    }

    /// Makes a random frame a reusable component, so instances and component deletes
    /// have more to work with.
    mutating func makeReusable(in doc: EditableDocument, nodeIDs: [String]) -> EditOperation? {
        let frames = nodeIDs.filter { id in
            if case .frame = doc.nodes[id]?.kind { return doc.nodes[id]?.common.reusable != true }
            return false
        }
        guard let nodeID = frames.randomElement(using: &rng) else { return nil }
        return .setProperties(EditOperation.SetProperties(nodeID: nodeID, properties: ["common.reusable": true]))
    }

    /// Overrides the name or opacity of one of a random instance's component descendants,
    /// or the width or fill of the instance's root.
    mutating func overrideInstance(in doc: EditableDocument, nodeIDs: [String], label: String, index: Int) -> EditOperation? {
        guard let refID = refs(in: doc, among: nodeIDs).randomElement(using: &rng),
              case let .ref(data) = doc.nodes[refID]?.kind else { return nil }
        let properties: [String: AnyCodable] = Bool.random(using: &rng)
            ? ["name": .string("\(label)\(index)")]
            : ["opacity": .double(Double(Int.random(in: 0 ... 10, using: &rng)) / 10)]
        let descendants = Array(doc.descendantIDs(of: data.ref).dropFirst())
        guard Bool.random(using: &rng), let descendantID = descendants.randomElement(using: &rng) else {
            // A root override names the component root's own keys; name and opacity
            // belong to the instance node itself.
            let root: [String: AnyCodable] = Bool.random(using: &rng)
                ? ["width": .int(Int.random(in: 1 ... 40, using: &rng) * 10)]
                : ["fill": .string(hexColor())]
            return .overrideRoot(EditOperation.OverrideRoot(refNodeID: refID, properties: root))
        }
        return .overrideDescendant(EditOperation.OverrideDescendant(refNodeID: refID, descendantID: descendantID, properties: properties))
    }

    /// A variable, theme-axis or import edit from the CRDT set.
    mutating func documentEntryEdit(in doc: EditableDocument) -> EditOperation? {
        switch Int.random(in: 0 ..< 3, using: &rng) {
        case 0: variableEdit(in: doc)
        case 1: themeAxisEdit(in: doc)
        default: importEdit(in: doc)
        }
    }

    /// Declares or drops a table, or sets the version, file token, fonts or a root extra.
    mutating func documentPropertyEdit(in _: EditableDocument, label: String, index: Int) -> EditOperation? {
        let property: (String, AnyCodable) = switch Int.random(in: 0 ..< 6, using: &rng) {
        case 0: (DocumentChangeKey.Table.allCases.randomElement(using: &rng)!.rawValue, Bool.random(using: &rng) ? .null : [:])
        case 1: ("version", Bool.random(using: &rng) ? "2.20" : "2.19")
        case 2: ("fileToken", Bool.random(using: &rng) ? .null : .string("\(label)\(index)"))
        case 3: ("fonts", Bool.random(using: &rng) ? .null : [["name": .string("Fuzz\(label)"), "url": .string("https://example.com/\(index).ttf")]])
        default: ("extras.fuzz\(Int.random(in: 0 ..< 2, using: &rng))", Bool.random(using: &rng) ? .null : .int(index))
        }
        return .setDocumentProperties(EditOperation.SetDocumentProperties(properties: [property.0: property.1]))
    }

    /// No preference, a declared empty list, or no `children` key.
    private mutating func emptyChildren() -> EditOperation.UpdateKind.EmptyChildren? {
        [nil, .declared, .absent].randomElement(using: &rng)!
    }
}
