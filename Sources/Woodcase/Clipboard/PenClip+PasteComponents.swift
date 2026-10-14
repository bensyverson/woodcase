//
//  PenClip+PasteComponents.swift
//  Woodcase
//

import Foundation

extension PenClip {
    /// A component a paste inserts under a new name.
    struct ComponentRename: Friendly {
        /// The component's id in the clip.
        var id: String

        /// Its name in the clip and in the target.
        var rename: PastePlan.Rename
    }

    /// The carried definitions the target already has: clip id → target id.
    ///
    /// A definition is reused when a target component — its own or an imported one — has
    /// the same name (its id, when it has none) and the same ``ComponentFingerprints``
    /// text, with the clip's variables read under the names the paste gives them. Where
    /// several target components qualify, the lowest id wins.
    ///
    /// - Parameters:
    ///   - carried: The clip's carried definitions.
    ///   - theirs: The target's components, own and imported, by id.
    ///   - variables: The paste's variable decisions.
    /// - Returns: The reused definitions.
    func reusedComponents(
        _ carried: [PenNode],
        among theirs: [String: PenNode],
        variables: PasteVariables
    ) -> [String: String] {
        var byKey: [String: [String]] = [:]
        for (id, component) in theirs {
            byKey[Self.key(of: component), default: []].append(id)
        }
        var mine = ComponentFingerprints(registry: Self.registry(of: document.children)) { variables.names[$0] ?? $0 }
        var target = ComponentFingerprints(registry: theirs) { $0 }
        var reused: [String: String] = [:]
        for definition in carried where definition.common.reusable == true {
            guard let text = mine.text(of: definition.id) else { continue }
            let match = (byKey[Self.key(of: definition)] ?? []).sorted().first { target.text(of: $0) == text }
            if let match {
                reused[definition.id] = match
            }
        }
        return reused
    }

    /// Every id inside the reused definitions, mapped to the target's node in the same
    /// place: equal fingerprints mean equal shapes, so pre-order pairs them.
    ///
    /// - Parameters:
    ///   - carried: The clip's carried definitions.
    ///   - reused: Clip id → target id, for the reused ones.
    ///   - theirs: The target's components, own and imported, by id.
    /// - Returns: Clip id → target id, for every node of every reused definition.
    static func positionalIDs(
        of carried: [PenNode],
        reusing reused: [String: String],
        among theirs: [String: PenNode]
    ) -> [String: String] {
        var ids: [String: String] = [:]
        for definition in carried {
            guard let match = reused[definition.id].flatMap({ theirs[$0] }) else { continue }
            for (old, new) in zip(Self.subtreeIDs(of: definition), Self.subtreeIDs(of: match)) {
                ids[old] = new
            }
        }
        return ids
    }

    /// The components a paste inserts whose names the target already holds, each given
    /// the first free number (``PasteNames/component(_:avoiding:)``), in the order they
    /// are inserted. A name two inserted components share is numbered on the second.
    ///
    /// - Parameters:
    ///   - inserted: The subtrees the paste inserts, in order.
    ///   - theirs: The target's components, own and imported, by id.
    /// - Returns: The renames.
    static func componentRenames(_ inserted: [PenNode], among theirs: [String: PenNode]) -> [ComponentRename] {
        var taken = Set(theirs.values.compactMap(\.common.name))
        var renames: [ComponentRename] = []
        var pending = Array(inserted.reversed())
        while let node = pending.popLast() {
            pending.append(contentsOf: node.kind.inlineChildren.reversed())
            guard node.common.reusable == true, let name = node.common.name else { continue }
            guard taken.contains(name) else {
                taken.insert(name)
                continue
            }
            let fresh = PasteNames.component(name, avoiding: taken)
            taken.insert(fresh)
            renames.append(ComponentRename(id: node.id, rename: PastePlan.Rename(from: name, to: fresh)))
        }
        return renames
    }

    /// The operations that give the target the theme axes the clip needs: an axis it
    /// lacks is added; one of its own that lacks options is widened, the new options
    /// appended so its first option stays its default. An axis it reads from a library
    /// is left as the library defines it.
    ///
    /// - Parameter document: The target.
    /// - Returns: The operations, by axis name.
    func themeOperations(in document: EditableDocument) -> [EditOperation] {
        let own = document.themes ?? [:]
        let imported = document.importedDefinitions.themes
        return (self.document.themes ?? [:]).sorted { $0.key < $1.key }.compactMap { name, options in
            if let existing = own[name] {
                let missing = options.filter { !existing.contains($0) }
                guard !missing.isEmpty else { return nil }
                return .updateThemeAxis(EditOperation.UpdateThemeAxis(name: name, options: existing + missing))
            }
            guard imported[name] == nil else { return nil }
            return .addThemeAxis(EditOperation.AddThemeAxis(name: name, options: options))
        }
    }

    /// What a component is matched by: its name, or its id when it has none.
    private static func key(of component: PenNode) -> String {
        component.common.name ?? component.id
    }

    /// Every component in a forest, by id, with its subtree.
    private static func registry(of roots: [PenNode]) -> [String: PenNode] {
        var registry: [String: PenNode] = [:]
        var pending = roots
        while let node = pending.popLast() {
            if node.common.reusable == true {
                registry[node.id] = node
            }
            pending.append(contentsOf: node.kind.inlineChildren)
        }
        return registry
    }
}
