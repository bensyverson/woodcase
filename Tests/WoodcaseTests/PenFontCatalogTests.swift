//
//  PenFontCatalogTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `PenFontRegistry.availableFamilies(cache:)` and `faces(of:cache:)`: the families and
/// faces Woodcase can draw — what Core Text has, registered or the system's, and what
/// the Google Fonts cache holds and a read would register.
struct PenFontCatalogTests {
    private static let fonts = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fonts")

    /// A cache root holding Lora's two variable files, as a download leaves them.
    private static func loraCache() throws -> (GoogleFontCache, URL) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let family = root.appendingPathComponent(GoogleFontCache.directoryName(for: "Lora"))
        try FileManager.default.createDirectory(at: family, withIntermediateDirectories: true)
        for file in ["Lora[wght].ttf", "Lora-Italic[wght].ttf"] {
            try FileManager.default.copyItem(
                at: fonts.appendingPathComponent("GoogleFonts").appendingPathComponent(file),
                to: family.appendingPathComponent(file)
            )
        }
        return (GoogleFontCache(rootDirectory: root), root)
    }

    /// An empty cache, so only Core Text answers.
    private static let noCache = GoogleFontCache(
        rootDirectory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    )

    private static func faces(_ family: String, _ weights: [Int], _ style: PenFontFace.Style) -> [PenFontFace] {
        weights.map { PenFontFace(family: family, weight: $0, style: style) }
    }

    // MARK: - Families

    @Test("The families include the system's and the default, sorted, with hidden ones left out")
    func families() {
        let families = PenFontRegistry.availableFamilies(cache: Self.noCache)
        #expect(families.contains("Helvetica"))
        #expect(families.contains(PenTextStyle.defaultFontFamily))
        #expect(!families.contains { $0.hasPrefix(".") })
        #expect(Set(families).count == families.count)
        #expect(families == families.sorted { $0.localizedStandardCompare($1) == .orderedAscending })
    }

    @Test("A family in the Google Fonts cache is listed before anything registers it")
    func cachedFamily() throws {
        let (cache, root) = try Self.loraCache()
        defer { try? FileManager.default.removeItem(at: root) }
        #expect(PenFontRegistry.availableFamilies(cache: cache).contains("Lora"))
    }

    // MARK: - Faces

    @Test("A static family lists each face it ships, in each style")
    func staticFaces() {
        let faces = PenFontRegistry.faces(of: "Helvetica", cache: Self.noCache)
        #expect(faces.contains(PenFontFace(family: "Helvetica", weight: 400, style: .normal)))
        #expect(faces.contains(PenFontFace(family: "Helvetica", weight: 700, style: .normal)))
        #expect(faces.contains(PenFontFace(family: "Helvetica", weight: 400, style: .italic)))
        #expect(faces == faces.sorted())
    }

    @Test("A registered static family lists exactly its cuts")
    func registeredStaticFaces() {
        TestFontRegistration.registerTestFonts()
        let family = "Woodcase Static Sans"
        #expect(PenFontRegistry.faces(of: family, cache: Self.noCache) == Self.faces(family, [400, 500, 600, 700], .normal))
    }

    @Test("A variable family lists every hundred its weight axis spans")
    func variableFaces() {
        TestFontRegistration.registerTestFonts()
        let faces = PenFontRegistry.faces(of: "Inter", cache: Self.noCache)
        #expect(faces == Self.faces("Inter", Array(stride(from: 100, through: 900, by: 100)), .normal))
    }

    @Test("A cached family's faces are read from its files, upright and italic")
    func cachedFaces() throws {
        let (cache, root) = try Self.loraCache()
        defer { try? FileManager.default.removeItem(at: root) }
        let expected = Self.faces("Lora", [400, 500, 600, 700], .normal) + Self.faces("Lora", [400, 500, 600, 700], .italic)

        #expect(PenFontRegistry.cachedFaces(in: cache)["Lora"].map { $0.sorted() } == expected.sorted())
        #expect(Set(PenFontRegistry.faces(of: "Lora", cache: cache)).isSuperset(of: expected))
    }

    @Test("A family Woodcase cannot draw has no faces")
    func unknownFamily() {
        #expect(PenFontRegistry.faces(of: "No Such Family Anywhere", cache: Self.noCache).isEmpty)
        #expect(!PenFontRegistry.faces(of: "Helvetica", cache: Self.noCache).isEmpty)
    }
}
