//
//  ThemedCustomProperty.swift
//  Woodcase
//

/// A CSS custom property the emitter derives from the document, with one value per theme.
///
/// Theme variables reach `theme.css` straight from the ``ThemeManifest``. A value the
/// emitter *computes* from them — a mesh gradient baked to a raster once per theme — is
/// declared the same way: under `:root` for the default theme and under a
/// `[data-axis="option"]` selector for each other one, so the element that uses it only
/// has to say `var(--name)` and the theme switch works exactly as it does for colours.
struct ThemedCustomProperty: Friendly {
    /// The property's name without its leading `--`, as `theme.css` spells variable names.
    var name: String

    /// The value under each theme, the default (empty conditions) among them.
    var values: [Value]

    /// One theme's value.
    struct Value: Friendly {
        /// The theme axes whose option differs from the default, e.g. `["mode": "dark"]`;
        /// empty for the default theme, which is declared on `:root`.
        var conditions: [String: String]

        /// The CSS value, written as is.
        var css: String
    }
}
