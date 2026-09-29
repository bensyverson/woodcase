//
//  CommandFixtureFontsTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
@testable import WoodcaseCommandCore

/// A regression guard for issue `e2iLwV`: no fixture a `shot`, `render` or `generate
/// swiftui` CLI test loads may name a `fontFamily`, because that download is real —
/// unless the test puts the family in the fixture's own font cache first
/// (``CommandFixture/seedFontCache(family:files:)``), which is what a `generate swiftui`
/// test that bundles fonts does.
///
/// `HermeticNetworkTests` (`Tests/WoodcaseTests`) proves the *library* suite never spells
/// a network-backed type, by reading test sources. It cannot see this gap: a
/// ``CommandFixture`` test never names `GoogleFontResolver` — it launches a real
/// `woodcase` binary as a subprocess, handed a fresh, empty `$WOODCASE_HOME` with none of
/// the test target's own CoreText registration or warm cache, and that subprocess's own
/// production font resolution is exactly what reaches GitHub. This suite reads the
/// *fixtures* those subprocesses render instead of the sources that launch them: for
/// every `@Test` in `Tests/WoodcaseCommandTests` that runs one of those verbs, every
/// `.pen` file it loads (directly or through ``CommandFixture/copy(fixture:)``) must name
/// no `fontFamily` at all, so every text node measures in
/// `PenTextMeasurer.defaultFontFamily` ("SF Pro"), resolved from the system font list
/// alone and never handed to `GoogleFontResolver`.
///
/// A test that genuinely needs a named, unresolvable, or Google-Fonts family — the
/// font-fallback UX itself is the subject, not incidental to it — runs a verb that
/// never downloads (`tree`, `lint`; see `SettledTree`'s `prepareCachedFonts`), which
/// this guard does not scan.
@Suite("CLI shot/render/generate fixtures stay hermetic")
struct CommandFixtureFontsTests {
    /// Marks the start of a `@Test` function in this codebase's style.
    private static let testMarker = "@Test("

    /// A `CommandFixture(fixture: "…")` construction.
    ///
    /// A computed property, not a stored one: a `Regex` is not `Sendable`, so a stored
    /// `static let` is a concurrency-safety error, and recompiling the literal on every
    /// access costs nothing a lint like this one needs to care about.
    private static var fixtureConstruction: Regex<(Substring, name: Substring)> {
        /CommandFixture\(fixture: "(?<name>[^"]+)"/
    }

    /// A `fixture.copy(fixture: "…")` call bringing in a second file.
    private static var secondaryFixture: Regex<(Substring, name: Substring)> {
        /\.copy\(fixture: "(?<name>[^"]+)"\)/
    }

    /// A `.run(...)` call whose first argument is `shot` or `render`, or whose first two
    /// are `generate`, `swiftui` (which fetches the fonts it bundles), in either the
    /// variadic or the array-literal form ``CommandFixture/run(_:environment:stdin:)``
    /// accepts.
    private static var networkVerbRun: Regex<(Substring, verb: Substring)> {
        /\.run\(\s*\[?\s*"(?<verb>shot|render|generate"\s*,\s*"swiftui)"/
    }

    /// A test that puts its families in the fixture's font cache before it runs.
    private static let seedsFontCache = ".seedFontCache("

    /// Every `.swift` file under `Tests/WoodcaseCommandTests`, whole.
    ///
    /// - Returns: Each file's path (relative to `Tests/WoodcaseCommandTests`) and text.
    /// - Throws: Whatever `FileManager` or `String(contentsOf:)` throws.
    private static func sources() throws -> [(path: String, code: String)] {
        let testsDirectory = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let enumerator = try #require(FileManager.default.enumerator(
            at: testsDirectory, includingPropertiesForKeys: nil
        ))
        var files: [(String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            files.append((
                url.path.replacingOccurrences(of: testsDirectory.path + "/", with: ""),
                text
            ))
        }
        return files
    }

    /// Splits a file's source at each ``testMarker``, so a fixture built inside one
    /// `@Test` is judged only against the verbs that same test runs.
    ///
    /// Text before the first marker (imports, the suite's doc comment) and any helper
    /// functions after the last `@Test` are folded into the neighboring chunk; neither
    /// constructs a fixture in this codebase today, so this stays a guard rather than a
    /// parser.
    ///
    /// - Parameter code: A whole source file.
    /// - Returns: One chunk per `@Test`, plus the leading chunk if the file has one.
    private static func testChunks(in code: String) -> [String] {
        var starts: [String.Index] = []
        var searchStart = code.startIndex
        while let range = code.range(of: Self.testMarker, range: searchStart ..< code.endIndex) {
            starts.append(range.lowerBound)
            searchStart = range.upperBound
        }
        guard !starts.isEmpty else { return [code] }
        return starts.enumerated().map { index, start in
            let end = index + 1 < starts.count ? starts[index + 1] : code.endIndex
            return String(code[start ..< end])
        }
    }

    /// The `fontFamily` strings a `.pen` document names, at any depth.
    ///
    /// - Parameter fixture: A file name inside `Tests/WoodcaseTests/Fixtures`.
    /// - Returns: Every distinct value found, including a `$`-prefixed variable
    ///   reference, which this guard treats as unresolved rather than chasing the
    ///   variable table.
    /// - Throws: Whatever ``CommandFixture/init(fixture:editedOutsideWoodcase:)`` or
    ///   `JSONSerialization` throws.
    private static func fontFamilies(in fixture: String) throws -> Set<String> {
        let copy = try CommandFixture(fixture: fixture)
        let data = try Data(contentsOf: copy.file)
        let object = try JSONSerialization.jsonObject(with: data)
        var found: Set<String> = []
        Self.walk(object) { key, value in
            guard key == "fontFamily", let family = value as? String else { return }
            found.insert(family)
        }
        return found
    }

    /// Visits every key/value pair in a decoded JSON tree.
    ///
    /// - Parameters:
    ///   - value: A `JSONSerialization` object: a dictionary, an array, or a leaf.
    ///   - visit: Called for every key/value pair found in a nested dictionary.
    private static func walk(_ value: Any, _ visit: (String, Any) -> Void) {
        if let dictionary = value as? [String: Any] {
            for (key, nested) in dictionary {
                visit(key, nested)
                walk(nested, visit)
            }
        } else if let array = value as? [Any] {
            for nested in array {
                walk(nested, visit)
            }
        }
    }

    @Test("Every fixture a shot/render/generate swiftui CLI test loads names no fontFamily it does not seed")
    func shotAndRenderFixturesNameNoFont() throws {
        var offenses: [String] = []
        for source in try Self.sources() {
            for chunk in Self.testChunks(in: source.code) where chunk.contains(Self.networkVerbRun) && !chunk.contains(Self.seedsFontCache) {
                var names = Set(chunk.matches(of: Self.fixtureConstruction).map { String($0.name) })
                names.formUnion(chunk.matches(of: Self.secondaryFixture).map { String($0.name) })
                for name in names.sorted() {
                    let families = try Self.fontFamilies(in: name)
                    guard !families.isEmpty else { continue }
                    offenses.append(
                        "\(source.path) shoots/renders \(name), which names fontFamily "
                            + "\(families.sorted()) — a fresh CommandFixture subprocess has "
                            + "no font cache and no CoreText registration, so this downloads"
                    )
                }
            }
        }
        #expect(offenses.isEmpty, "\(offenses.joined(separator: "\n"))")
    }
}
