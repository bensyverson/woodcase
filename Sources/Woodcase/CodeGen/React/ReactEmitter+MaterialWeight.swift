//
//  ReactEmitter+MaterialWeight.swift
//  Woodcase
//

extension ReactEmitter {
    /// The warning for a Material Symbols icon whose weight the package cannot draw exactly.
    static func steppedMaterialWeightWarning(_ weight: Int) -> String {
        "React draws this Material Symbols icon at weight \(weight): the package has weights in steps of 100"
    }

    /// Warns once for a Material Symbols icon whose own `weight` is not one the package
    /// ships, so it is drawn at the nearest (``IconLibraryMapping/materialWeight(_:)``).
    static func warnSteppedMaterialWeight(_ node: PenNode, data: PenNode.IconData, family: String, ctx: EmitContext) {
        guard family.hasPrefix("Material Symbols "), let weight = data.weight?.literalValue else { return }
        let drawn = IconLibraryMapping.materialWeight(weight)
        guard Double(drawn) != weight else { return }
        ctx.warnOnce(steppedMaterialWeightWarning(drawn), nodeID: node.id)
    }
}
