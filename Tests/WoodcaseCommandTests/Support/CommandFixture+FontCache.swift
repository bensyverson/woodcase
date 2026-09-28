//
//  CommandFixture+FontCache.swift
//  WoodcaseCommandTests
//

import Foundation
import Woodcase

extension CommandFixture {
    /// The committed test fonts (`Tests/WoodcaseTests/Fonts`).
    static let testFonts = packageRoot.appendingPathComponent("Tests/WoodcaseTests/Fonts", isDirectory: true)

    /// Puts committed test fonts into this fixture's own font cache as `family`'s cached
    /// files, with the METADATA.pb that says which face each file is, so a run that
    /// resolves `family`'s faces finds them on disk and never downloads anything.
    ///
    /// This is what keeps a verb that may download — `shot`, `render`, `generate` — on a
    /// fixture that names a family hermetic; `CommandFixtureFontsTests` accepts a test
    /// that calls it.
    ///
    /// - Parameters:
    ///   - family: The family name, as a text node's `fontFamily` writes it.
    ///   - files: Paths inside `Tests/WoodcaseTests/Fonts` (`GoogleFonts/IBMPlexMono-Bold.ttf`),
    ///     each file named as Google Fonts names a face (`-Regular`, `-Bold`, `-Italic`…, or
    ///     `Family[axes].ttf` for a variable one); the name is how the METADATA.pb written
    ///     beside them gives each its weight. Each lands in the cache under its file name.
    /// - Throws: Whatever `FileManager` throws.
    func seedFontCache(family: String, files: [String]) throws {
        let directory = home
            .appendingPathComponent("fonts", isDirectory: true)
            .appendingPathComponent(GoogleFontCache.directoryName(for: family), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let names = files.map { URL(fileURLWithPath: $0).lastPathComponent }
        for (file, name) in zip(files, names) {
            try FileManager.default.copyItem(
                at: Self.testFonts.appendingPathComponent(file), to: directory.appendingPathComponent(name)
            )
        }
        let entries = names.map { file in
            let face = Self.face(of: file)
            return "fonts {\n  style: \"\(face.style)\"\n  weight: \(face.weight)\n  filename: \"\(file)\"\n}\n"
        }
        try Data(("name: \"\(family)\"\n" + entries.joined()).utf8)
            .write(to: directory.appendingPathComponent("METADATA.pb"))
    }

    /// The weight and style a Google Fonts file name spells: `IBMPlexMono-BoldItalic.ttf` is
    /// 700 italic; a variable file (`IBMPlexSans[wdth,wght].ttf`) is 400.
    private static func face(of file: String) -> (weight: Int, style: String) {
        let stem = file.split(separator: ".").first.map(String.init) ?? file
        let suffix = stem.split(separator: "-").last.map(String.init) ?? ""
        let italic = suffix.hasSuffix("Italic")
        let weights = [
            "Thin": 100, "ExtraLight": 200, "Light": 300, "Regular": 400, "Medium": 500,
            "SemiBold": 600, "Bold": 700, "ExtraBold": 800, "Black": 900,
        ]
        let name = italic ? String(suffix.dropLast("Italic".count)) : suffix
        return (weights[name] ?? 400, italic ? "italic" : "normal")
    }
}
