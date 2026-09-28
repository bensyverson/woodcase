//
//  SwiftUITheme+Variants.swift
//  Woodcase
//

extension SwiftUITheme {
    /// One theme a preview or the catalog draws a view under: the default, or one axis set
    /// to one of its other options.
    struct Variant: Friendly {
        /// What a preview calls it — `mode: dark` — or `nil` for the default theme.
        var name: String?

        /// The modifier that selects it — `.penTheme(mode: .dark)` — or `nil` for the
        /// default theme, which needs none.
        var modifier: String?
    }

    /// The themes a view is previewed under: the default, then each axis's other options one
    /// at a time, in axis order.
    ///
    /// One axis at a time, not every combination: the sum of the axes' options stays small
    /// where their product does not (banking's three axes are 16 combinations, and 6
    /// variants one at a time), and the
    /// catalog's pickers reach every combination.
    var variants: [Variant] {
        var variants = [Variant(name: nil, modifier: nil)]
        for axis in axes {
            for option in axis.options.dropFirst() {
                variants.append(Variant(
                    name: "\(axis.name): \(option.value)",
                    modifier: ".penTheme(\(axis.property): \(option.member))"
                ))
            }
        }
        return variants
    }
}
