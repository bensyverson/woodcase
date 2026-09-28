//
//  ReactHarnessBuilder+IconStubs.swift
//  Woodcase
//

import Foundation

extension ReactHarnessBuilder {
    /// One icon a page's code imports from an icon package.
    struct IconImport: Friendly {
        /// The .pen icon family whose package the import names.
        let family: String
        /// The name the package exports (`VpnLock`).
        let imported: String
        /// The name the code draws it by: `imported`, or its alias (`VpnLockRounded`).
        let local: String
        /// The `wght` a Material Symbols import path draws, or `nil` for a family with no
        /// weight axis.
        let weight: Int?
    }

    /// Every icon the `files` import from a recognized icon package, once each, sorted by
    /// local name: `import { VpnLock as VpnLockRounded } from "…/rounded/200"` is one.
    static func iconImports(in files: [GeneratedFile]) -> [IconImport] {
        let pattern: Regex<(Substring, Substring, Substring)> = /import\s*\{([^}]+)\}\s*from\s*"([^"]+)"/
        var icons: [String: IconImport] = [:]
        for file in files {
            for match in file.content.matches(of: pattern) {
                let path = String(match.output.2)
                guard let family = IconLibraryMapping.family(forImportPath: path) else { continue }
                let weight = IconLibraryMapping.materialWeight(forImportPath: path)
                for specifier in match.output.1.split(separator: ",") {
                    let words = specifier.split(whereSeparator: \.isWhitespace).map(String.init)
                    guard let imported = words.first else { continue }
                    let local = words.count == 3 && words[1] == "as" ? words[2] : imported
                    icons[local] = IconImport(family: family, imported: imported, local: local, weight: weight)
                }
            }
        }
        return icons.values.sorted { $0.local < $1.local }
    }

    /// Generates a stub React component for an icon, an empty SVG placeholder matching the
    /// icon's size: the fallback when the page has no icon fonts.
    static func iconStub(_ name: String) -> String {
        """
        function \(name)({ size = 24, color = "currentColor", ...props }) {
          return React.createElement("svg", {
            width: size, height: size, viewBox: "0 0 24 24",
            fill: "none", stroke: color, strokeWidth: 2,
            strokeLinecap: "round", strokeLinejoin: "round",
            ...props
          });
        }
        """
    }

    /// One `@font-face` per bundled font file of each family `icons` use, at
    /// `relativePath`, named for the family as the stubs ask for it.
    static func buildIconFontFaceCSS(for icons: [IconImport], relativePath: String) -> String {
        Set(icons.map(\.family)).sorted().flatMap { family in
            PenIconFontRegistry.shared.fontFileURLs(for: family).map { url in
                """
                @font-face {
                  font-family: '\(family)';
                  src: url('\(relativePath)/\(url.lastPathComponent)') format('truetype');
                }\n
                """
            }
        }.joined()
    }

    /// Builds one stub per icon, drawing its glyph in its family's bundled font.
    ///
    /// Each glyph is the codepoint ``PenIconFontRegistry`` — the table the CG renderer
    /// draws from — gives the icon the component name stands for, picked by codepoint
    /// rather than ligature, which fails silently where a font has no ligature for a name.
    /// A Phosphor stub carries a glyph per weight, as the package draws its `weight` prop.
    /// Every glyph is set at the font's default optical size, as the CG renderer draws it:
    /// WebKit would set a variable Material Symbols face at the optical size of its point size.
    /// A Material Symbols stub sets the `wght` its import path names, as the package ships
    /// one path per weight and takes no weight prop.
    static func buildIconFontStubs(for icons: [IconImport]) -> String {
        let factory = """
        function __iconGlyph__(fontFamily, glyphs, variation) {
          return function({ size = 24, color = "currentColor", weight, style, ...props }) {
            var glyph = glyphs[weight] || glyphs.regular;
            return React.createElement("span", {
              "aria-hidden": true,
              ...props,
              style: Object.assign({
                fontFamily: fontFamily,
                fontSize: size,
                lineHeight: 1,
                color: color,
                display: "inline-grid",
                placeItems: "center",
                width: size,
                height: size,
                WebkitFontSmoothing: "antialiased",
                fontOpticalSizing: "none",
                fontVariationSettings: variation || "normal",
                overflow: "hidden",
              }, style || {}),
            }, glyph);
          };
        }
        """
        let stubs = icons.map { icon in
            let glyphs = glyphs(for: icon).map { "\($0.weight): \"\($0.glyph)\"" }.joined(separator: ", ")
            let variation = icon.weight.map { ", \"'wght' \($0)\"" } ?? ""
            return "const \(icon.local) = __iconGlyph__(\"\(icon.family)\", { \(glyphs) }\(variation));"
        }
        return ([factory] + stubs).joined(separator: "\n")
    }

    /// The glyphs `icon`'s stub draws, `regular` first, each a JavaScript string escape;
    /// the family's placeholder when no icon of the family makes the component name.
    private static func glyphs(for icon: IconImport) -> [(weight: String, glyph: String)] {
        let registry = PenIconFontRegistry.shared
        let escape = { (codepoint: UInt32) in "\\u{\(String(codepoint, radix: 16, uppercase: true))}" }
        guard let name = penIconName(for: icon), let regular = registry.codepoint(family: icon.family, name: name) else {
            return registry.placeholder(family: icon.family).map { [("regular", escape($0.codepoint))] } ?? []
        }
        var glyphs = [(weight: "regular", glyph: escape(regular))]
        if icon.family == "phosphor" {
            for weight in IconLibraryMapping.phosphorWeights.sorted() {
                if let codepoint = registry.codepoint(family: icon.family, name: "\(name)-\(weight)") {
                    glyphs.append((weight, escape(codepoint)))
                }
            }
        }
        return glyphs
    }

    /// The .pen icon name whose component in `icon`'s family is the name imported — the
    /// shortest, so a Phosphor icon's base name wins over its weights'.
    private static func penIconName(for icon: IconImport) -> String? {
        (PenIconFontRegistry.shared.names(in: icon.family) ?? [])
            .filter { IconLibraryMapping.resolve(family: icon.family, iconName: $0)?.componentName == icon.imported }
            .min { ($0.count, $0) < ($1.count, $1) }
    }
}
