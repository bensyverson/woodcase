//
//  IconLibraryMapping+MaterialWeight.swift
//  Woodcase
//

extension IconLibraryMapping {
    /// The Material Symbols package every style and weight is imported from.
    static let materialPackage = "@nine-thirty-five/material-symbols-react"

    /// The weight Pen draws a Material Symbols icon at when the node sets none: `getIconPath`
    /// sets only the `wght` axis, at 200 (eb2a33d), as the CG renderer does.
    static let materialDefaultWeight = 200

    /// The weight the package's bare style path draws, `…/outlined`.
    static let materialBareWeight = 400

    /// The weights the package ships, one import path each.
    static let materialWeights = 100 ... 700

    /// The package weight that draws a node's `weight`: `weight` rounded to the nearest
    /// hundred and kept within the package's 100–700, or ``materialDefaultWeight`` when the
    /// node sets none.
    ///
    /// The package takes no weight prop: each weight is its own import path,
    /// `…/{style}[/{weight}]`, in steps of 100 (its README, version 2.4.4), where Pen's axis
    /// is continuous.
    static func materialWeight(_ weight: Double?) -> Int {
        guard let weight else { return materialDefaultWeight }
        let hundreds = Int((weight / 100).rounded(.toNearestOrAwayFromZero)) * 100
        return min(max(hundreds, materialWeights.lowerBound), materialWeights.upperBound)
    }

    /// The import path of one style at one weight: the bare style path for 400, the
    /// package's own spelling of its default, else the style with the weight.
    static func materialImportPath(variant: String, weight: Int) -> String {
        let base = "\(materialPackage)/\(variant)"
        return weight == materialBareWeight ? base : "\(base)/\(weight)"
    }

    /// The weight a Material Symbols import path draws — its weight segment, or 400 for a
    /// bare style path — or `nil` for a path that is not one of the package's styles.
    public static func materialWeight(forImportPath path: String) -> Int? {
        materialImport(path)?.weight
    }

    /// The family and weight a Material Symbols import path names, or `nil` for any other
    /// path, or a weight the package does not ship.
    static func materialImport(_ path: String) -> (family: String, weight: Int)? {
        guard let match = path.wholeMatch(of: /@nine-thirty-five\/material-symbols-react\/(outlined|rounded|sharp)(?:\/(\d+))?/)
        else { return nil }
        let weight = match.output.2.flatMap { Int($0) } ?? materialBareWeight
        guard materialWeights.contains(weight), weight % 100 == 0 else { return nil }
        return ("Material Symbols \(match.output.1.prefix(1).uppercased())\(match.output.1.dropFirst())", weight)
    }
}
