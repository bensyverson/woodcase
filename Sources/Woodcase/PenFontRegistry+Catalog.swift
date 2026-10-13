//
//  PenFontRegistry+Catalog.swift
//  Woodcase
//

import CoreText
import Foundation
import os

/// The font families and faces Woodcase can draw a text in: what a font menu offers.
///
/// Two sources, because a text can be drawn in either. **Core Text**: the system's
/// families and every one registered in this process — a document's declared fonts,
/// Google faces already fetched, a host's own. **The Google Fonts cache**
/// (``GoogleFontCache``): families downloaded on an earlier run that nothing has
/// registered yet, which the read path registers from disk, without the network, the
/// moment a document names them (``GoogleFontResolver/prepareCachedFonts(for:diagnostics:)``).
/// A cached family is listed under the name its files carry, which is the name a
/// `fontFamily` must say.
///
/// Both answers are cached until ``generation`` moves, which every registration does.
///
/// ```swift
/// PenFontRegistry.availableFamilies()            // ["Avenir", "Helvetica", "Inter", "Lora", …]
/// PenFontRegistry.faces(of: "Lora").map(\.weight) // [400, 500, 600, 700, 400, 500, 600, 700]
/// ```
public extension PenFontRegistry {
    /// Every family Woodcase can draw, sorted as Finder sorts names.
    ///
    /// The families the system hides from font menus (`.AppleSystemUIFont`) are left
    /// out, and Woodcase's default family (``PenTextStyle/defaultFontFamily``) is always
    /// in: it is what a text that names no family, or one Woodcase cannot find, is set in.
    ///
    /// - Parameter cache: The Google Fonts cache to read as well. Defaults to
    ///   `$WOODCASE_HOME/fonts`; an editor with a cache directory of its own passes it.
    /// - Returns: The family names, each once.
    static func availableFamilies(cache: GoogleFontCache = GoogleFontCache()) -> [String] {
        let key = CatalogKey(generation: generation, cacheRoot: cache.rootDirectory.path)
        if let cached = catalog.withLock({ $0.families[key] }) { return cached }
        var families = Set(registeredFamilies().filter { !$0.hasPrefix(hiddenPrefix) })
        families.formUnion(cachedFaces(in: cache).keys)
        families.insert(PenTextStyle.defaultFontFamily)
        let sorted = families.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        catalog.withLock { $0.families = [key: sorted] }
        return sorted
    }

    /// The faces of one family Woodcase can draw, lightest first and upright before
    /// italic at each weight.
    ///
    /// A static font is the face its weight class names (`Bold` is 700); a variable one
    /// is every hundred its weight axis spans, so a 400–700 family lists 400, 500, 600 and
    /// 700. Woodcase can set any weight in a family — it draws the nearest face, as CSS
    /// does — so these are the weights drawn in a face of their own, which is what a
    /// weight menu offers.
    ///
    /// - Parameters:
    ///   - family: The family name, as a `fontFamily` writes it.
    ///   - cache: The Google Fonts cache to read as well.
    /// - Returns: The faces, empty for a family Woodcase cannot draw.
    static func faces(of family: String, cache: GoogleFontCache = GoogleFontCache()) -> [PenFontFace] {
        let key = CatalogKey(generation: generation, cacheRoot: cache.rootDirectory.path)
        if let cached = catalog.withLock({ $0.faces[key]?[family] }) { return cached }
        let registered = FontRegistryGate.withAccess {
            registeredFonts(of: family).flatMap { faces(of: $0, as: family) }
        }
        let directory = cache.rootDirectory.appendingPathComponent(GoogleFontCache.directoryName(for: family))
        let cached = cachedFaces(inDirectories: [directory])[family] ?? []
        let faces = Set(registered).union(cached).sorted()
        catalog.withLock { state in
            if state.faces[key] == nil { state.faces = [key: [:]] }
            state.faces[key]?[family] = faces
        }
        return faces
    }
}

extension PenFontRegistry {
    /// The faces each family in the Google Fonts cache holds, read from its files without
    /// registering them.
    ///
    /// - Parameter cache: The cache to read.
    /// - Returns: Family name → faces, keyed by the family name the files carry.
    static func cachedFaces(in cache: GoogleFontCache) -> [String: Set<PenFontFace>] {
        let directories = (try? FileManager.default.contentsOfDirectory(
            at: cache.rootDirectory, includingPropertiesForKeys: nil
        )) ?? []
        return cachedFaces(inDirectories: directories)
    }

    // MARK: - Private

    /// What the catalog was read against: the font set, and the cache directory.
    private struct CatalogKey: Hashable {
        let generation: Int
        let cacheRoot: String
    }

    /// The last answers, each kept only for the key it was read at.
    private struct Catalog {
        var families: [CatalogKey: [String]] = [:]
        var faces: [CatalogKey: [String: [PenFontFace]]] = [:]
    }

    private static let catalog = OSAllocatedUnfairLock(initialState: Catalog())

    /// The prefix of the families the system keeps out of font menus.
    private static let hiddenPrefix = "."

    /// The size fonts are opened at to read their traits; any size reads the same.
    private static let catalogPointSize: CGFloat = 12

    /// The weights a variable face is listed at: CSS's nine.
    private static let listedWeights = stride(from: 100, through: 900, by: 100)

    /// Every family Core Text can draw.
    private static func registeredFamilies() -> [String] {
        FontRegistryGate.withAccess {
            (CTFontManagerCopyAvailableFontFamilyNames() as? [String]) ?? []
        }
    }

    /// Every font Core Text holds for exactly `family`.
    private static func registeredFonts(of family: String) -> [CTFont] {
        let request = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
        let mandatory = Set([kCTFontFamilyNameAttribute]) as CFSet
        let matches = (CTFontDescriptorCreateMatchingFontDescriptors(request, mandatory) as? [CTFontDescriptor]) ?? []
        return matches.map { CTFontCreateWithFontDescriptor($0, catalogPointSize, nil) }
            .filter { (CTFontCopyFamilyName($0) as String).caseInsensitiveCompare(family) == .orderedSame }
    }

    /// The faces the font files in these cache directories hold, by the family name the
    /// files carry. A directory that does not exist holds none.
    private static func cachedFaces(inDirectories directories: [URL]) -> [String: Set<PenFontFace>] {
        var result: [String: Set<PenFontFace>] = [:]
        for directory in directories {
            let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil))
                ?? []
            for file in files where GoogleFontCache.fontExtensions.contains(file.pathExtension.lowercased()) {
                FontRegistryGate.withAccess {
                    let descriptors = (CTFontManagerCreateFontDescriptorsFromURL(file as CFURL) as? [CTFontDescriptor])
                        ?? []
                    for descriptor in descriptors {
                        let font = CTFontCreateWithFontDescriptor(descriptor, catalogPointSize, nil)
                        let family = CTFontCopyFamilyName(font) as String
                        result[family, default: []].formUnion(faces(of: font, as: family))
                    }
                }
            }
        }
        return result
    }

    /// The faces one font draws in a face of its own.
    private static func faces(of font: CTFont, as family: String) -> [PenFontFace] {
        let style: PenFontFace.Style = CTFontGetSymbolicTraits(font).contains(.traitItalic) ? .italic : .normal
        let weights = PenTextMeasurer.drawnWeights(of: font)
        let listed: [Int] = weights.lowerBound == weights.upperBound
            ? [weights.lowerBound]
            : listedWeights.filter(weights.contains)
        return listed.map { PenFontFace(family: family, weight: $0, style: style) }
    }
}
