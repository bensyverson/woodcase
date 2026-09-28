//
//  EmitContext+IconImports.swift
//  Woodcase
//

extension EmitContext {
    /// One icon a file imports: the name its package exports it under, from one import path.
    struct IconBinding: Friendly {
        /// The .pen icon family (`"lucide"`, `"Material Symbols Rounded"`).
        var family: String
        /// The component name the family's package exports (`"VpnLock"`).
        var name: String
        /// The path it is imported from, which for Material Symbols also picks the weight
        /// (`"…/rounded/200"`).
        var importPath: String
    }

    /// The name the file draws `name` of `family`, from `importPath`, by, recording its import.
    ///
    /// The package's own name, unless the file already means something else by it: a
    /// reserved name (``CodeGenName/reservedNames``: lucide's `Map`), a component's or the
    /// file's own, or the same name from another path. Then the icon is imported under an
    /// alias: its name followed by its family's word (``IconLibraryMapping/identifierSuffix(for:)``)
    /// — `Map as MapLucide`, `VpnLock as VpnLockRounded` — or, when the same family already
    /// took the name at another Material weight, by its weight (`VpnLock as VpnLock700`);
    /// numbered from 2 should that be taken too. The first path to use a name in the file
    /// keeps it.
    func iconLocalName(_ name: String, family: String, importPath: String) -> String {
        let binding = IconBinding(family: family, name: name, importPath: importPath)
        if let bound = iconBindings.first(where: { $0.value == binding }) {
            return bound.key
        }
        let componentNames = Set(componentRegistry.values.map(\.name))
        let isTaken: (String) -> Bool = { candidate in
            self.iconBindings[candidate] != nil || CodeGenName.reservedNames.contains(candidate)
                || candidate == self.ownName || componentNames.contains(candidate)
        }
        let sameFamily = iconBindings.values.contains { $0.family == family && $0.name == name }
        let suffix = sameFamily
            ? IconLibraryMapping.materialWeight(forImportPath: importPath).map(String.init) ?? ""
            : IconLibraryMapping.identifierSuffix(for: family)
        let local = isTaken(name) ? CodeGenName.numbered(name + suffix, isTaken: isTaken) : name
        iconBindings[local] = binding
        iconImports[importPath, default: []].insert(local == name ? name : "\(name) as \(local)")
        return local
    }
}
