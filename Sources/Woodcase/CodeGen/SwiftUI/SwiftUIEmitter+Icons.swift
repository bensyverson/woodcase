//
//  SwiftUIEmitter+Icons.swift
//  Woodcase
//

import Foundation

public extension SwiftUIEmitter {
    /// The font files an icon library's glyphs are drawn from, which `woodcase generate
    /// swiftui` copies into `Sources/<Module>/Resources/` beside the images; empty for a
    /// library with no bundled font.
    static func iconFontFiles(for library: String) -> [URL] {
        PenIconFontRegistry.shared.fontFileURLs(for: library)
    }

    /// The icon libraries `node` and its descendants draw from whose fonts the package
    /// bundles, by the family names the .pen file writes (`"lucide"`).
    static func iconLibraries(in node: PenNode) -> Set<String> {
        guard node.common.enabled?.literalValue != false else { return [] }
        switch node.kind {
        case let .icon(data):
            guard let library = data.library?.literalValue, !iconFontFiles(for: library).isEmpty else { return [] }
            return [library]
        case let .frame(data):
            return (data.children ?? []).reduce(into: Set<String>()) { $0.formUnion(iconLibraries(in: $1)) }
        case let .group(data):
            return (data.children ?? []).reduce(into: Set<String>()) { $0.formUnion(iconLibraries(in: $1)) }
        default:
            return []
        }
    }
}
