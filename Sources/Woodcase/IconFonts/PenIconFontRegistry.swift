//
//  PenIconFontRegistry.swift
//  Woodcase
//

import CoreGraphics
import CoreText
import Foundation
import os

/// Manages icon font registration and codepoint lookups for rendering `icon` nodes.
///
/// The registry lazily registers bundled icon fonts on first use and provides
/// codepoint lookups for icon names across all supported font families.
///
/// Supported built-in families:
/// - `lucide`
/// - `feather`
/// - `phosphor` (v1 — all weight variants in a single font)
/// - `Material Symbols Outlined`
/// - `Material Symbols Rounded`
/// - `Material Symbols Sharp`
///
/// Users can register additional icon fonts via ``register(family:fontName:mapping:)``.
public final class PenIconFontRegistry: Sendable {
    /// Shared singleton instance.
    public static let shared = PenIconFontRegistry()

    /// Result of resolving an icon: the codepoint and the CTFont family name to render with.
    public struct ResolvedIcon: Sendable {
        public let codepoint: UInt32
        public let ctFontName: String
    }

    /// Maps `.pen` family name → CTFont family name for built-in fonts.
    private static let builtInFontNames: [String: String] = [
        "lucide": "lucide",
        "feather": "icomoon",
        "phosphor": "Phosphor",
        "Material Symbols Outlined": "Material Symbols Outlined",
        "Material Symbols Rounded": "Material Symbols Rounded",
        "Material Symbols Sharp": "Material Symbols Sharp",
    ]

    /// Maps `.pen` family name → TTF filenames to register for bundled fonts.
    private static let builtInFontFiles: [String: [String]] = [
        "lucide": ["lucide.ttf"],
        "feather": ["feather.ttf"],
        "phosphor": ["Phosphor.ttf"],
        "Material Symbols Outlined": ["MaterialSymbolsOutlined.ttf"],
        "Material Symbols Rounded": ["MaterialSymbolsRounded.ttf"],
        "Material Symbols Sharp": ["MaterialSymbolsSharp.ttf"],
    ]

    /// Maps `.pen` family name → codepoint dictionary for built-in fonts.
    private static let builtInCodepoints: [String: [String: UInt32]] = [
        "lucide": LucideCodepoints.codepoints,
        "feather": FeatherCodepoints.codepoints,
        "phosphor": PhosphorCodepoints.codepoints,
        "Material Symbols Outlined": MaterialSymbolsCodepoints.codepoints,
        "Material Symbols Rounded": MaterialSymbolsCodepoints.codepoints,
        "Material Symbols Sharp": MaterialSymbolsCodepoints.codepoints,
    ]

    /// Maps `.pen` family name → the name of that family's own "unknown icon" glyph:
    /// what Pen.app's own engine draws in place of an `icon` node whose name is not
    /// in the library (verified with `pen interactive` — see leaf AuqQs), and what
    /// ``placeholder(family:)`` resolves for the same case.
    private static let builtInPlaceholderNames: [String: String] = [
        "lucide": "circle-question-mark",
        "feather": "help-circle",
        "phosphor": "question",
        "Material Symbols Outlined": "help",
        "Material Symbols Rounded": "help",
        "Material Symbols Sharp": "help",
    ]

    private struct State {
        /// Set of `.pen` family names whose fonts have been registered with CoreText.
        var registeredFamilies: Set<String> = []
        /// User-registered custom families: `.pen` family name → codepoint mapping.
        var customCodepoints: [String: [String: UInt32]] = [:]
        /// User-registered custom font names: `.pen` family name → CTFont family name.
        var customFontNames: [String: String] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    private init() {}

    // MARK: - Public API

    /// Resolve an icon to its codepoint and the CTFont family name needed to render it.
    ///
    /// For most families this is straightforward. For phosphor, the icon name may
    /// include a weight suffix (e.g. `"chat-dots-thin"`) which selects a different
    /// font variant (`Phosphor-Thin`) while sharing the same codepoint as the base name.
    ///
    /// - Parameters:
    ///   - family: The `.pen` family name (e.g. `"lucide"`, `"phosphor"`).
    ///   - name: The icon name (e.g. `"bell"`, `"chat-dots-thin"`).
    /// - Returns: A ``ResolvedIcon`` with the codepoint and font name, or `nil` if unknown.
    public func resolve(family: String, name: String) -> ResolvedIcon? {
        ensureRegistered(family)

        // Check custom families first
        if let customMapping = state.withLock({ $0.customCodepoints[family] }),
           let cp = customMapping[name],
           let fontName = state.withLock({ $0.customFontNames[family] })
        {
            return ResolvedIcon(codepoint: cp, ctFontName: fontName)
        }

        guard let mapping = Self.builtInCodepoints[family] else {
            return nil
        }

        // Direct lookup
        if let cp = mapping[name], let fontName = Self.builtInFontNames[family] {
            return ResolvedIcon(codepoint: cp, ctFontName: fontName)
        }

        // Material Symbols: try replacing hyphens with underscores
        if family.hasPrefix("Material Symbols") {
            let underscored = name.replacingOccurrences(of: "-", with: "_")
            if underscored != name, let cp = mapping[underscored],
               let fontName = Self.builtInFontNames[family]
            {
                return ResolvedIcon(codepoint: cp, ctFontName: fontName)
            }
        }

        return nil
    }

    /// Resolve a built-in family's own "unknown icon" placeholder glyph.
    ///
    /// This is deliberately separate from ``resolve(family:name:)``: the
    /// `unknown-icon` lint check (<doc:WoodcaseLint>) detects an unresolvable name by
    /// `resolve(family:name:) == nil`, so folding the placeholder into that method
    /// would silence the lint finding it exists to raise. Only a renderer — which
    /// wants pixels on the page rather than a diagnostic — should call this.
    ///
    /// - Parameter family: The `.pen` family name.
    /// - Returns: The placeholder's ``ResolvedIcon``, or `nil` when `family` has no
    ///   bundled placeholder — an unknown family, or a custom family registered via
    ///   ``register(family:fontName:mapping:)``, which carries no placeholder name.
    public func placeholder(family: String) -> ResolvedIcon? {
        ensureRegistered(family)
        guard let placeholderName = Self.builtInPlaceholderNames[family],
              let mapping = Self.builtInCodepoints[family],
              let cp = mapping[placeholderName],
              let fontName = Self.builtInFontNames[family]
        else {
            return nil
        }
        return ResolvedIcon(codepoint: cp, ctFontName: fontName)
    }

    /// Look up the Unicode codepoint for an icon by family and name.
    ///
    /// Convenience wrapper around ``resolve(family:name:)`` for cases where
    /// only the codepoint is needed.
    public func codepoint(family: String, name: String) -> UInt32? {
        resolve(family: family, name: name)?.codepoint
    }

    /// The CTFont family name to use when creating a font for this `.pen` family.
    ///
    /// - Parameter family: The `.pen` family name.
    /// - Returns: The CTFont family name, or `nil` if the family is unknown.
    public func fontName(for family: String) -> String? {
        if let custom = state.withLock({ $0.customFontNames[family] }) {
            return custom
        }
        return Self.builtInFontNames[family]
    }

    /// The bundled font file URLs backing a built-in family.
    ///
    /// These are the same files ``resolve(family:name:)`` registers with CoreText,
    /// resolved via ``WoodcaseResources`` — useful for consumers (such as a WebView
    /// harness) that need to load the actual font file rather than render with it.
    ///
    /// - Parameter family: The `.pen` family name.
    /// - Returns: File URLs into the package's bundled resources, or an empty
    ///   array if `family` has no bundled fonts (e.g. a custom-registered family) or the
    ///   resource bundle cannot be found.
    public func fontFileURLs(for family: String) -> [URL] {
        guard let filenames = Self.builtInFontFiles[family],
              let bundle = try? WoodcaseResources.bundle() else { return [] }
        return filenames.compactMap { filename in
            bundle.url(forResource: filename, withExtension: nil, subdirectory: "Fonts")
        }
    }

    /// Every icon name `family`'s table maps, or `nil` if `family` is not registered.
    ///
    /// Covers both bundled families and any registered via
    /// ``register(family:fontName:mapping:)``. This is what `woodcase icons` lists and
    /// what ``IconNameMatcher`` searches to propose a fix for an unresolved name.
    ///
    /// - Parameter family: The `.pen` family name.
    /// - Returns: The family's icon names, in no particular order, or `nil` if
    ///   `family` is registered nowhere.
    public func names(in family: String) -> [String]? {
        if let custom = state.withLock({ $0.customCodepoints[family] }) {
            return Array(custom.keys)
        }
        return Self.builtInCodepoints[family].map { Array($0.keys) }
    }

    /// Every icon library this registry currently knows, sorted: the six bundled
    /// families plus any registered via ``register(family:fontName:mapping:)``.
    public var libraries: [String] {
        let custom = state.withLock { Array($0.customCodepoints.keys) }
        return Array(Set(Self.builtInCodepoints.keys).union(custom)).sorted()
    }

    /// Register a custom icon font family.
    ///
    /// - Parameters:
    ///   - family: The `.pen` family name to register.
    ///   - fontName: The CTFont family name (as registered with CoreText).
    ///   - mapping: A dictionary of icon name → Unicode codepoint.
    public func register(family: String, fontName: String, mapping: [String: UInt32]) {
        state.withLock {
            $0.customCodepoints[family] = mapping
            $0.customFontNames[family] = fontName
        }
    }

    // MARK: - Font Registration

    /// Ensures the bundled fonts for the given family are registered with CoreText.
    private func ensureRegistered(_ family: String) {
        let needsRegistration = state.withLock {
            !$0.registeredFamilies.contains(family)
        }

        guard needsRegistration else { return }

        // Moves the font generation only for a file Core Text did not already have.
        for fontURL in fontFileURLs(for: family) {
            PenFontRegistry.registerFont(at: fontURL)
        }

        // Mark as registered regardless of success to avoid retrying.
        state.withLock {
            _ = $0.registeredFamilies.insert(family)
        }
    }
}
