//
//  IconLibraryMapping.swift
//  Woodcase
//

/// Maps icon font family names to their React npm package details.
///
/// Supports Lucide, Feather, Phosphor, and Material Symbols icon families,
/// providing the correct npm package name, ES import path, and component
/// name conversion for each.
public enum IconLibraryMapping {
    /// The resolved result for an icon: which component to import and from where.
    public struct Resolution: Friendly {
        /// The React component name to import (e.g. `"ArrowLeft"`).
        public var componentName: String
        /// The npm package to install (e.g. `"lucide-react"`).
        public var npmPackage: String
        /// The ES import path (e.g. `"@nine-thirty-five/material-symbols-react/outlined"`).
        public var importPath: String
        /// Additional props to pass to the component (e.g. `["weight": "bold"]`).
        public var extraProps: [String: String]

        public init(
            componentName: String,
            npmPackage: String,
            importPath: String,
            extraProps: [String: String] = [:]
        ) {
            self.componentName = componentName
            self.npmPackage = npmPackage
            self.importPath = importPath
            self.extraProps = extraProps
        }
    }

    /// Known Phosphor weight suffixes that should be stripped from the icon name.
    static let phosphorWeights: Set<String> = [
        "bold", "fill", "light", "thin", "duotone",
    ]

    /// Resolves an icon family and name to its React import details.
    ///
    /// - Parameters:
    ///   - family: The .pen icon font family (e.g. `"lucide"`, `"phosphor"`,
    ///     `"Material Symbols Outlined"`).
    ///   - iconName: The icon name in its native format (e.g. `"arrow-left"`,
    ///     `"chat-dots-bold"`, `"vpn_lock"`).
    ///   - weight: The node's `weight`, which picks a Material Symbols icon's import path
    ///     (``materialWeight(_:)``); other families ignore it.
    /// - Returns: A ``Resolution`` with the component name, package, and import path,
    ///   or `nil` if the family is not supported.
    public static func resolve(family: String, iconName: String, weight: Double? = nil) -> Resolution? {
        switch family {
        case "lucide":
            Resolution(
                componentName: kebabToPascal(iconName),
                npmPackage: "lucide-react",
                importPath: "lucide-react"
            )

        case "feather":
            Resolution(
                componentName: kebabToPascal(iconName),
                npmPackage: "react-feather",
                importPath: "react-feather"
            )

        case "phosphor":
            resolvePhosphor(iconName: iconName)

        case "Material Symbols Outlined":
            resolveMaterial(iconName: iconName, variant: "outlined", weight: weight)

        case "Material Symbols Rounded":
            resolveMaterial(iconName: iconName, variant: "rounded", weight: weight)

        case "Material Symbols Sharp":
            resolveMaterial(iconName: iconName, variant: "sharp", weight: weight)

        default:
            nil
        }
    }

    /// Returns the ES import path for a given icon family name — for a Material Symbols
    /// style, its bare path, which draws weight 400; ``resolve(family:iconName:weight:)``
    /// gives the path of the weight an icon draws.
    public static func importPath(for family: String) -> String? {
        switch family {
        case "lucide":
            "lucide-react"
        case "feather":
            "react-feather"
        case "phosphor":
            "@phosphor-icons/react"
        case "Material Symbols Outlined":
            "@nine-thirty-five/material-symbols-react/outlined"
        case "Material Symbols Rounded":
            "@nine-thirty-five/material-symbols-react/rounded"
        case "Material Symbols Sharp":
            "@nine-thirty-five/material-symbols-react/sharp"
        default:
            nil
        }
    }

    /// Returns the npm package name for a given icon family.
    public static func npmPackage(for family: String) -> String? {
        switch family {
        case "lucide":
            "lucide-react"
        case "feather":
            "react-feather"
        case "phosphor":
            "@phosphor-icons/react"
        case "Material Symbols Outlined", "Material Symbols Rounded", "Material Symbols Sharp":
            "@nine-thirty-five/material-symbols-react"
        default:
            nil
        }
    }

    /// Returns the canonical family name for a given import path, or `nil` if unrecognized:
    /// any Material Symbols style path, with or without a weight the package ships.
    public static func family(forImportPath path: String) -> String? {
        switch path {
        case "lucide-react":
            "lucide"
        case "react-feather":
            "feather"
        case "@phosphor-icons/react":
            "phosphor"
        default:
            materialImport(path)?.family
        }
    }

    // MARK: - Phosphor

    private static func resolvePhosphor(iconName: String) -> Resolution {
        let parts = iconName.split(separator: "-")

        // Check if the last segment is a known weight suffix
        var weight: String?
        var baseParts = parts
        if let last = parts.last, phosphorWeights.contains(String(last)) {
            weight = String(last)
            baseParts = Array(parts.dropLast())
        }

        let componentName = baseParts
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined() + "Icon"

        var extraProps: [String: String] = [:]
        if let weight {
            extraProps["weight"] = weight
        }

        return Resolution(
            componentName: componentName,
            npmPackage: "@phosphor-icons/react",
            importPath: "@phosphor-icons/react",
            extraProps: extraProps
        )
    }

    // MARK: - Material Symbols

    private static func resolveMaterial(iconName: String, variant: String, weight: Double?) -> Resolution {
        // Normalize: replace hyphens with underscores
        let normalized = iconName.replacingOccurrences(of: "-", with: "_")

        // Split on underscores
        let parts = normalized.split(separator: "_")

        // Convert to PascalCase, handling leading digits
        let componentName = parts
            .enumerated()
            .map { index, part -> String in
                let str = String(part)
                if let leadingDigits = extractLeadingDigits(str) {
                    let word = numberToWords(leadingDigits.number)
                    let rest = leadingDigits.remainder
                    if index == 0, rest.isEmpty {
                        return word
                    } else if rest.isEmpty {
                        return word
                    } else {
                        return word + rest.prefix(1).uppercased() + rest.dropFirst()
                    }
                }
                return str.prefix(1).uppercased() + str.dropFirst()
            }
            .joined()

        return Resolution(
            componentName: componentName,
            npmPackage: "@nine-thirty-five/material-symbols-react",
            importPath: materialImportPath(variant: variant, weight: materialWeight(weight))
        )
    }

    // MARK: - Utilities

    /// Converts kebab-case to PascalCase: `"arrow-left"` → `"ArrowLeft"`.
    private static func kebabToPascal(_ name: String) -> String {
        name.split(separator: "-")
            .map { $0.prefix(1).uppercased() + $0.dropFirst() }
            .joined()
    }

    /// Extracts leading digits from a string, returning the numeric value and remainder.
    private static func extractLeadingDigits(_ str: String) -> (number: Int, remainder: String)? {
        var digits = ""
        for char in str {
            if char.isNumber {
                digits.append(char)
            } else {
                break
            }
        }
        guard !digits.isEmpty, let number = Int(digits) else { return nil }
        return (number, String(str.dropFirst(digits.count)))
    }

    /// Converts an integer (0–999) to PascalCase English words.
    ///
    /// Examples: `18` → `"Eighteen"`, `123` → `"OneHundredTwentyThree"`.
    public static func numberToWords(_ n: Int) -> String {
        guard n >= 0, n <= 999 else { return String(n) }

        let ones = [
            "", "One", "Two", "Three", "Four", "Five", "Six", "Seven", "Eight", "Nine",
            "Ten", "Eleven", "Twelve", "Thirteen", "Fourteen", "Fifteen", "Sixteen",
            "Seventeen", "Eighteen", "Nineteen",
        ]
        let tens = [
            "", "", "Twenty", "Thirty", "Forty", "Fifty", "Sixty", "Seventy", "Eighty", "Ninety",
        ]

        if n == 0 { return "Zero" }

        var result = ""
        var remainder = n

        if remainder >= 100 {
            result += ones[remainder / 100] + "Hundred"
            remainder %= 100
        }

        if remainder >= 20 {
            result += tens[remainder / 10]
            remainder %= 10
        }

        if remainder > 0 {
            result += ones[remainder]
        }

        return result
    }
}
