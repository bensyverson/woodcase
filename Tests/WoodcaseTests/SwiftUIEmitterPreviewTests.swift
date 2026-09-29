//
//  SwiftUIEmitterPreviewTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The `#Preview`s every emitted view ends with: one per state a caller can pin, and each
/// of those again under every theme option other than the default, one axis at a time.
struct SwiftUIEmitterPreviewTests {
    @Test("A themed component is previewed under each non-default option, one axis at a time")
    func themedComponentVariants() throws {
        let file = try component("StatCard", in: "woodcase-app")
        #expect(file.contains("#Preview {\n    StatCard()\n        .frame(width: 120)\n}"))
        #expect(file.contains("#Preview(\"density: compact\") {\n    StatCard()\n        .frame(width: 120)\n        .penTheme(density: .compact)\n}"))
        #expect(file.contains("#Preview(\"mode: dark\") {\n    StatCard()\n        .frame(width: 120)\n        .penTheme(mode: .dark)\n}"))
        // One axis at a time, not their product.
        #expect(!file.contains("density: .compact, mode: .dark"))
    }

    @Test("Every state's preview is repeated under each theme variant")
    func statesTimesThemes() throws {
        let file = try component("ToggleView", in: "woodcase-app")
        #expect(file.contains("#Preview(\"off\") {\n    ToggleView(isOn: .constant(false))\n        .frame(width: 44, height: 26)\n}"))
        #expect(file.contains("#Preview(\"off, mode: dark\") {\n    ToggleView(isOn: .constant(false))\n        .frame(width: 44, height: 26)\n        .penTheme(mode: .dark)\n}"))
        #expect(file.contains(
            "#Preview(\"disabled, density: compact\") {\n    ToggleView()\n        .frame(width: 44, height: 26)\n        .disabled(true)\n        .penTheme(density: .compact)\n}"
        ))
    }

    @Test("A themed page is previewed under each theme variant too")
    func themedPageVariants() throws {
        let pages = try SwiftUIFixtures.emit("render-theme-axis").files.filter { $0.path.contains("/Pages/") }
        let screen = try #require(pages.first { $0.path.hasSuffix("/Screen.swift") })
        #expect(screen.content.contains("#Preview {\n    Screen()\n}"))
        #expect(screen.content.contains("#Preview(\"mode: dark\") {\n    Screen()\n        .penTheme(mode: .dark)\n}"))
    }

    @Test("The theme variants are the default and every other option of each axis, in axis order")
    func variantsOfTheme() throws {
        let document = try SwiftUIFixtures.document("woodcase-app")
        let theme = try #require(SwiftUITheme(ThemeAnalyzer.analyze(document)))
        #expect(theme.variants.map(\.name) == [nil, "density: compact", "mode: dark"])
        #expect(theme.variants.map(\.modifier) == [nil, ".penTheme(density: .compact)", ".penTheme(mode: .dark)"])
    }

    /// The emitted source of the component `type` in `fixture`.
    private func component(_ type: String, in fixture: String) throws -> String {
        let files = try SwiftUIFixtures.emit(fixture).files
        return try #require(files.first { $0.path.hasSuffix("/Components/\(type).swift") }).content
    }
}
