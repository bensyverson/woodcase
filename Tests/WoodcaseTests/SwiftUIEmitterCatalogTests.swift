//
//  SwiftUIEmitterCatalogTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The catalog the SwiftUI package carries — `Catalog/PenCatalog.swift`, the sheet of every
/// component in its states, the theme's tokens and its type, and a picker per theme axis —
/// and the `<Module>Catalog` executable that opens it in a window.
struct SwiftUIEmitterCatalogTests {
    /// The fixtures whose catalogs are pinned whole.
    static let fixtures = ["woodcase-app", "pages", "codegen-states"]

    // MARK: - Package

    @Test("Package.swift declares the catalog executable beside the library")
    func manifestDeclaresTheExecutable() throws {
        let manifest = try file("Package.swift", in: "layout-nested", module: "Acme")
        #expect(manifest.contains(#".executable(name: "AcmeCatalog", targets: ["AcmeCatalog"]),"#))
        #expect(manifest.contains(#".executableTarget(name: "AcmeCatalog", dependencies: ["Acme"]),"#))
        #expect(manifest.contains(#".library(name: "Acme", targets: ["Acme"]),"#))
    }

    @Test("The catalog lives under Catalog/ in the module and the executable in its own target")
    func catalogLayout() throws {
        let paths = try SwiftUIFixtures.emit("layout-nested", options: .init(moduleName: "Acme")).files.map(\.path)
        #expect(paths.contains("Sources/Acme/Catalog/PenCatalog.swift"))
        #expect(paths.contains("Sources/Acme/Catalog/PenCatalogSheet.swift"))
        #expect(paths.contains("Sources/Acme/Catalog/PenCatalogThemes.swift"))
        #expect(paths.contains("Sources/AcmeCatalog/main.swift"))
    }

    @Test("The executable opens the catalog in a window, or renders it to a PNG with --snapshot")
    func executableMain() throws {
        let main = try file("Sources/AcmeCatalog/main.swift", in: "layout-nested", module: "Acme")
        #expect(main.contains("import Acme\n"))
        #expect(main.contains("\"--snapshot\""))
        #expect(main.contains("ImageRenderer(content: PenCatalogThemes())"))
        #expect(main.contains("WindowGroup(\"Acme\") {\n                PenCatalog()"))
        #expect(main.contains("AcmeCatalogApp.main()"))
        #expect(main.contains("setActivationPolicy(.regular)"))
    }

    // MARK: - The sheet

    @Test("The sheet draws every component in each state a caller can pin")
    func sheetDrawsEveryState() throws {
        let sheet = try file("Sources/PenUI/Catalog/PenCatalogSheet.swift", in: "codegen-states")
        #expect(sheet.contains("PenCatalogSpecimen(\"default\") {\n                        StatesButton()\n                    }"))
        #expect(sheet.contains("PenCatalogSpecimen(\"pressed\") {\n                        StatesButton()\n                            .penControlState(.pressed)\n                    }"))
        #expect(sheet.contains("Switch(isOn: .constant(false))"))
        #expect(sheet.contains("SortSelect(variant: .open)"))
        #expect(sheet.contains("PenCatalogEntry(\"Chip\")"))
    }

    @Test("The sheet shows each colour token as a swatch and each other token as its value")
    func sheetShowsTokens() throws {
        let sheet = try file("Sources/PenUI/Catalog/PenCatalogSheet.swift", in: "woodcase-app")
        #expect(sheet.contains("@Environment(\\.penTheme) private var theme"))
        #expect(sheet.contains("PenCatalogSwatch(\"$accent\", color: theme.accent)"))
        #expect(sheet.contains("PenCatalogValue(\"$card-radius\", value: Double(theme.cardRadius).formatted())"))
        #expect(sheet.contains("PenCatalogValue(\"$font-primary\", value: theme.fontPrimary)"))
    }

    @Test("The sheet sets each text style the document uses, largest first")
    func sheetShowsType() throws {
        let sheet = try file("Sources/PenUI/Catalog/PenCatalogSheet.swift", in: "woodcase-app")
        let largest = try #require(sheet.range(of: ".penFont(theme.fontPrimary, size: 48"))
        let smallest = try #require(sheet.range(of: ".penFont(theme.fontPrimary, size: 10"))
        #expect(largest.lowerBound < smallest.lowerBound)
        #expect(sheet.contains("PenCatalogSpecimen(\"$font-primary 14 600\")"))
        #expect(sheet.contains(".penFont(theme.fontPrimary, size: theme.fontSizeBody"))
    }

    @Test("The sheet draws every page")
    func sheetDrawsPages() throws {
        let sheet = try file("Sources/PenUI/Catalog/PenCatalogSheet.swift", in: "pages")
        #expect(sheet.contains("PenCatalogEntry(\"Home\") {\n                    Home()"))
        #expect(sheet.contains("PenCatalogEntry(\"About\") {\n                    About()"))
        #expect(sheet.contains("PenCatalogEntry(\"Card\")"))
    }

    @Test("A document without themes has a sheet that reads no theme and a catalog with no picker")
    func unthemedCatalog() throws {
        let sheet = try file("Sources/PenUI/Catalog/PenCatalogSheet.swift", in: "pages")
        let catalog = try file("Sources/PenUI/Catalog/PenCatalog.swift", in: "pages")
        let themes = try file("Sources/PenUI/Catalog/PenCatalogThemes.swift", in: "pages")
        for source in [sheet, catalog, themes] {
            #expect(!source.contains("PenTheme"))
            #expect(!source.contains("penTheme"))
        }
        #expect(!catalog.contains("Picker"))
    }

    // MARK: - The window and the themes

    @Test("The catalog has a picker per theme axis and draws the sheet under the picked theme")
    func catalogPicksTheTheme() throws {
        let catalog = try file("Sources/PenUI/Catalog/PenCatalog.swift", in: "woodcase-app")
        #expect(catalog.contains("@State private var theme = PenTheme()"))
        #expect(catalog.contains("Picker(\"density\", selection: $theme.density)"))
        #expect(catalog.contains("Picker(\"mode\", selection: $theme.mode)"))
        #expect(catalog.contains(".penTheme(density: theme.density, mode: theme.mode)"))
    }

    @Test("The catalog's body is the sheet in a scroll view of both axes, sized to the window it is in")
    func catalogScrolls() throws {
        for fixture in ["woodcase-app", "pages"] {
            let catalog = try file("Sources/PenUI/Catalog/PenCatalog.swift", in: fixture)
            #expect(catalog.contains(
                "    public var body: some View {\n        GeometryReader { window in\n            ScrollView([.horizontal, .vertical]) {\n                PenCatalogSheet()\n                    .penCatalogViewport(window.size)"
            ), "\(fixture)")
        }
        // The viewport's background is inside the picked theme, so a dark theme fills the window.
        let themed = try file("Sources/PenUI/Catalog/PenCatalog.swift", in: "woodcase-app")
        #expect(themed.contains(".penCatalogViewport(window.size)\n                    .penTheme(density: theme.density, mode: theme.mode)"))
    }

    @Test("The sheet's stack sits on the catalog's page: margins, filling its room, on the background")
    func sheetIsAPage() throws {
        let sheet = try file("Sources/PenUI/Catalog/PenCatalogSheet.swift", in: "pages")
        #expect(sheet.contains("        }\n        .penCatalogPage()\n    }\n}"))
    }

    @Test("Rows wrap at the width the window sets, and place as they were measured")
    func flowWrapsAtTheWindow() throws {
        let layout = try #require(SwiftUIEmitter.supportTemplates()["PenSupport+CatalogLayout.swift"])
        #expect(layout.contains("@Entry var penCatalogRowWidth"))
        #expect(layout.contains("environment(\\.penCatalogRowWidth, max(0, size.width - 2 * PenCatalogMetrics.margin))"))
        #expect(layout.contains("for (subview, frame) in zip(subviews, arrange(subviews, proposal: proposal))"))
        #expect(layout.contains("subview.sizeThatFits(.unspecified)"))
    }

    @Test("PenCatalogThemes sets the sheet side by side under every theme variant")
    func themesSideBySide() throws {
        let themes = try file("Sources/PenUI/Catalog/PenCatalogThemes.swift", in: "woodcase-app")
        #expect(themes.contains("PenCatalogSheet()\n"))
        #expect(themes.contains("PenCatalogSheet()\n                    .penTheme(density: .compact)"))
        #expect(themes.contains("PenCatalogSheet()\n                    .penTheme(mode: .dark)"))
        #expect(themes.contains("PenCatalogColumn(\"mode: dark\")"))
    }

    @Test("A component named like a catalog type is suffixed View")
    func catalogNamesAreShadowed() throws {
        let json = ##"""
        {"version": "2.17", "children": [
          {"type": "frame", "id": "c1", "name": "PenCatalog", "reusable": true, "width": 10, "height": 10},
          {"type": "frame", "id": "c2", "name": "PenCatalogSheet", "reusable": true, "width": 10, "height": 10}
        ]}
        """##
        let document = try PenParser.parse(Data(json.utf8))
        let names = SwiftUIEmitter.componentTypeNames(ComponentAnalyzer.analyze(document))
        #expect(names["c1"] == "PenCatalogView")
        #expect(names["c2"] == "PenCatalogSheetView")
    }

    // MARK: - Goldens

    @Test("Each fixture's catalog files match their goldens", arguments: fixtures)
    func catalogMatchesGoldens(fixture: String) throws {
        let files = try SwiftUIFixtures.emit(fixture).files
            .filter { $0.path.contains("/Catalog/") || $0.path.hasPrefix("Sources/PenUICatalog/") }
        #expect(files.count == 4)
        for file in files {
            let name = URL(fileURLWithPath: file.path).lastPathComponent
            try GoldenFile.assert(file.content, name: name, subdirectory: "swiftui/\(fixture)/Catalog")
        }
    }

    // MARK: - Helpers

    /// The content of the file at `path` that `fixture` emits.
    private func file(_ path: String, in fixture: String, module: String = "PenUI") throws -> String {
        let files = try SwiftUIFixtures.emit(fixture, options: .init(moduleName: module)).files
        return try #require(files.first { $0.path == path }, "\(fixture) emitted no \(path)").content
    }
}
