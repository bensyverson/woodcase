//
//  SwiftUIComponentScope+Faces.swift
//  Woodcase
//

extension SwiftUIComponentScope {
    /// This scope inside the face `variant` of `component` — the frame the designer drew for
    /// one of its states: each prop bound at the node its path names in the variant's tree,
    /// where that node can carry it, so a pressed button's label still reads `label`, and
    /// each slot drawn in the frame its path names there.
    func drawing(_ component: SwiftUIComponent, face variant: PenNode) -> Self {
        var scope = drawing(component)
        var bound: [String: [SwiftUIProp]] = [:]
        for prop in component.props {
            guard let node = ComponentAnalyzer.resolveDescendantPath(prop.definition.path, from: variant) else { continue }
            var unemitted: [String] = []
            guard SwiftUIProp(prop.definition, target: node, unemitted: &unemitted)?.kind == prop.kind else { continue }
            bound[node.id, default: []].append(prop)
        }
        scope.bound = bound
        scope.slots = [:]
        for slot in component.slots {
            guard let node = ComponentAnalyzer.resolveDescendantPath(slot.path, from: variant), case .frame = node.kind else { continue }
            scope.slots[node.id] = slot
        }
        return scope
    }

    /// This scope with the first text of `tree` drawn as the component's `TextField`.
    func typing(in tree: PenNode) -> Self {
        var scope = self
        var pending = [tree]
        while !pending.isEmpty {
            let node = pending.removeFirst()
            if case .text = node.kind {
                scope.textField = node.id
                return scope
            }
            pending.insert(contentsOf: ComponentAnalyzer.childNodes(of: node), at: 0)
        }
        return scope
    }
}
