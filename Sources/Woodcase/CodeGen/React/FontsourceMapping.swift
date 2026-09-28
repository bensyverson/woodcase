//
//  FontsourceMapping.swift
//  Woodcase
//

/// Maps font family names to their Fontsource npm package names and CSS imports.
///
/// Fontsource packages follow a consistent naming convention:
/// `@fontsource/<slug>` where `<slug>` is the font family name
/// lowercased with spaces replaced by hyphens.
public enum FontsourceMapping {
    /// Returns the Fontsource npm package name for a font family.
    ///
    /// Example: `"IBM Plex Sans"` → `"@fontsource/ibm-plex-sans"`.
    public static func packageName(for family: String) -> String {
        "@fontsource/\(slug(for: family))"
    }

    /// Returns the CSS `@import` statement for loading a font via Fontsource.
    ///
    /// Example: `"IBM Plex Sans"` → `@import "@fontsource/ibm-plex-sans";`.
    public static func cssImport(for family: String) -> String {
        "@import \"\(packageName(for: family))\";"
    }

    private static func slug(for family: String) -> String {
        family.lowercased().replacingOccurrences(of: " ", with: "-")
    }
}
