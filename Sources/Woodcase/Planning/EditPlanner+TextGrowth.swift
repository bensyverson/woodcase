//
//  EditPlanner+TextGrowth.swift
//  Woodcase
//

import Foundation

/// Changing a text's `textGrowth` keeps the size it is drawn at (Penumbra spec §4.4, the
/// integrator's ruling of 2026-10-15, leaf Q2hXKO).
///
/// `textGrowth` says which of a text's `fit_content` dimensions follow its words: `auto`
/// both, `fixed-width` the height, `fixed-width-height` neither. A `fit_content` dimension
/// that stops following them reads its fallback — 0 by default — so a text set from auto to
/// fixed width turned 0 wide and very tall. So a set or override of `textGrowth` also writes
/// each dimension that stops following the words as the number it was drawn at, and drops
/// the number of each that starts following them again, so it does. A dimension the caller
/// writes in the same edit, or one that fills its container, is left as it is.
extension EditPlanner {
    /// The intent, with the sizes a change of `textGrowth` keeps or drops added to it.
    ///
    /// - Parameters:
    ///   - intent: What the caller asked for.
    ///   - target: The node it is aimed at.
    ///   - document: The document, as it stands.
    /// - Returns: `intent` itself unless it changes a text's growth so that a dimension
    ///   starts or stops following its words.
    static func keepingTextSize(
        _ intent: EditIntent,
        at target: ResolvedNodeAddress,
        in document: EditableDocument
    ) -> EditIntent {
        switch intent {
        case let .set(properties):
            guard case let .node(id) = target, let node = document.node(id: id) else { return intent }
            let writes = textSizeWrites(properties, unset: [], on: node, at: target, dropping: .null, in: document)
            return writes.isEmpty ? intent : .set(properties.merging(writes) { asked, _ in asked })
        case let .override(properties, unset):
            // The node as this instance shows it, its overrides applied, is in the expanded
            // tree; it is expanded only for an override that changes the growth.
            guard case .instanceDescendant = target, writesGrowth(properties),
                  let node = shownNode(document.expandedID(of: target), in: document.expandedDocument().0.children)
            else { return intent }
            let writes = textSizeWrites(
                properties, unset: unset, on: node, at: target, dropping: .string(fitContent), in: document
            )
            return writes.isEmpty ? intent : .override(properties.merging(writes) { asked, _ in asked }, unset: unset)
        case .resetOverride, .bind, .unbind:
            return intent
        }
    }

    /// The size writes a change of a text's growth needs.
    ///
    /// - Parameters:
    ///   - properties: The values the caller writes, by property path or raw key.
    ///   - unset: The keys the caller removes.
    ///   - node: The text as it is shown now.
    ///   - target: Where it is drawn, to read its drawn size.
    ///   - dropping: What a dimension that follows the words again is written as: `null`
    ///     on a node's own storage, `fit_content` in an override, which must outweigh the
    ///     component's number.
    ///   - document: The document, as it stands.
    /// - Returns: Property path → value; empty when nothing changes.
    private static func textSizeWrites(
        _ properties: [String: AnyCodable],
        unset: [String],
        on node: PenNode,
        at target: ResolvedNodeAddress,
        dropping: AnyCodable,
        in document: EditableDocument
    ) -> [String: AnyCodable] {
        guard case let .text(data) = node.kind,
              let asked = (properties[growthPath] ?? properties[growthKey]).flatMap(growth(from:))
        else { return [:] }
        let current = data.textGrowth ?? .auto
        guard asked != current else { return [:] }

        let written = Set(properties.keys.map(NodePropertyCodec.rawKey(for:)) + unset.map(NodePropertyCodec.rawKey(for:)))
        var fixing: [String] = []
        var writes: [String: AnyCodable] = [:]
        for (path, sizing, follows) in [
            (widthPath, PenLayoutEngine.widthSizing(of: node), { (growth: PenTextGrowth) in growth == .auto }),
            (heightPath, PenLayoutEngine.heightSizing(of: node), { (growth: PenTextGrowth) in growth != .fixedWidthHeight }),
        ] where !written.contains(NodePropertyCodec.rawKey(for: path)) {
            switch (follows(current), follows(asked), sizing) {
            case (true, false, .fitContent):
                fixing.append(path)
            case (false, true, .fixed):
                writes[path] = dropping
            default:
                break
            }
        }
        if !fixing.isEmpty {
            let layout = PenLayoutState(document: PenVariableResolver.resolve(document.expandedDocument().0))
            if let size = layout.rects[document.expandedID(of: target)]?.drawnSize {
                for path in fixing {
                    writes[path] = number(path == widthPath ? size.width : size.height)
                }
            }
        }
        return writes
    }

    /// Whether a write names a text's growth.
    private static func writesGrowth(_ properties: [String: AnyCodable]) -> Bool {
        properties[growthPath] != nil || properties[growthKey] != nil
    }

    /// A node of an expanded tree, found by its expanded id.
    private static func shownNode(_ id: String, in roots: [PenNode]) -> PenNode? {
        var pending = roots
        while let node = pending.popLast() {
            if node.id == id { return node }
            pending += node.kind.inlineChildren
        }
        return nil
    }

    /// The growth a written value names, or `nil` for one that names none — which the
    /// value checks then refuse. A `null` removes the key, which reads as `auto`.
    private static func growth(from value: AnyCodable) -> PenTextGrowth? {
        switch value {
        case let .string(raw): PenTextGrowth(rawValue: raw)
        case .null: .auto
        default: nil
        }
    }

    /// The property path of a text's growth.
    private static let growthPath = NodePropertyCodec.kindPrefix + growthKey

    /// The raw key of a text's growth, as an override may write it.
    private static let growthKey = "textGrowth"

    /// How a dimension that follows its content is written.
    private static let fitContent = "fit_content"
}
