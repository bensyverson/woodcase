//
//  ReactEmitter+Utilities.swift
//  Woodcase
//

extension ReactEmitter {
    // MARK: - Utility

    /// The Tailwind class for a literal gap: a class on Tailwind's spacing scale where one
    /// matches, otherwise an arbitrary value such as `gap-[30px]`, so no gap is dropped.
    static func tailwindGap(_ value: Double) -> String {
        // Tailwind gap scale: 1=0.25rem=4px
        let mapping: [Double: String] = [
            0: "gap-0", 1: "gap-px", 2: "gap-0.5", 4: "gap-1",
            6: "gap-1.5", 8: "gap-2", 10: "gap-2.5", 12: "gap-3",
            14: "gap-3.5", 16: "gap-4", 20: "gap-5", 24: "gap-6",
            28: "gap-7", 32: "gap-8",
        ]
        return mapping[value] ?? "gap-[\(cssNumber(value))px]"
    }

    static func typescriptType(for propType: PropType) -> String {
        switch propType {
        case .string: "string"
        case .color: "string"
        case .boolean: "boolean"
        case .imageURL: "string"
        }
    }

    static func formatDefaultValue(_ prop: PropDefinition) -> String {
        guard let defaultValue = prop.defaultValue else { return "" }
        switch defaultValue {
        case let .string(s): return " = \"\(s)\""
        case let .bool(b): return " = \(b)"
        case let .int(n): return " = \(n)"
        case let .double(d): return " = \(d)"
        default: return ""
        }
    }

    static func formatPx(_ value: Double) -> String {
        if value == 0 { return "0px" }
        if value == value.rounded(), !value.isInfinite { return "\(Int(value))px" }
        return "\(value)px"
    }

    // MARK: - Utility File Emission

    static func emitCnUtility() -> GeneratedFile {
        let content = """
        import { clsx, type ClassValue } from "clsx";
        import { twMerge } from "tailwind-merge";

        export function cn(...inputs: ClassValue[]) {
          return twMerge(clsx(inputs));
        }

        """
        return GeneratedFile(path: "lib/cn.ts", content: content)
    }

    static func emitThemeProvider(theme: ThemeManifest) -> GeneratedFile {
        var lines: [String] = []

        lines.append("import { createContext, useContext, useState } from \"react\";")
        lines.append("")

        // Type definition
        lines.append("type ThemeContextType = {")
        for axis in theme.axes {
            lines.append("  \(axis.name): string;")
            lines.append("  set\(axis.name.capitalizingFirst): (v: string) => void;")
        }
        lines.append("};")
        lines.append("")

        // Default values
        let defaultEntries = theme.axes.map { axis in
            let defaultValue = axis.values.first ?? ""
            return "\(axis.name): \"\(defaultValue)\", set\(axis.name.capitalizingFirst): () => {}"
        }.joined(separator: ", ")
        lines.append("const ThemeContext = createContext<ThemeContextType>({ \(defaultEntries) });")
        lines.append("")

        // Provider component
        lines.append("export function ThemeProvider({ children }: { children: React.ReactNode }) {")
        for axis in theme.axes {
            let defaultValue = axis.values.first ?? ""
            lines.append("  const [\(axis.name), set\(axis.name.capitalizingFirst)] = useState(\"\(defaultValue)\");")
        }
        lines.append("")

        // Value object
        let valueEntries = theme.axes.map { axis in
            "\(axis.name), set\(axis.name.capitalizingFirst)"
        }.joined(separator: ", ")
        lines.append("  return (")
        lines.append("    <ThemeContext.Provider value={{ \(valueEntries) }}>")

        // Data attributes div
        let dataAttrs = theme.axes.map { "data-\($0.name)={\($0.name)}" }.joined(separator: " ")
        lines.append("      <div \(dataAttrs)>")
        lines.append("        {children}")
        lines.append("      </div>")
        lines.append("    </ThemeContext.Provider>")
        lines.append("  );")
        lines.append("}")
        lines.append("")
        lines.append("export const useTheme = () => useContext(ThemeContext);")

        return GeneratedFile(
            path: "ThemeProvider.tsx",
            content: lines.joined(separator: "\n") + "\n"
        )
    }
}

// MARK: - String Helpers

extension String {
    var capitalizingFirst: String {
        guard let first else { return self }
        return first.uppercased() + dropFirst()
    }
}
