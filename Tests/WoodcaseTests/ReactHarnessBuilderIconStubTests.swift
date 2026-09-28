//
//  ReactHarnessBuilderIconStubTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The icon stubs ``ReactHarnessBuilder`` writes in place of the icon packages: each
/// draws its own family's glyph in that family's bundled font, so a page's Material
/// Symbols, Feather and Phosphor icons measure the emitter rather than the harness.
@Suite("ReactHarnessBuilder icon stubs")
struct ReactHarnessBuilderIconStubTests {
    private static let iconFontDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .appendingPathComponent("Sources/Woodcase/IconFonts/Fonts")

    /// The harness page for a component `Card` whose file imports `imports`.
    private static func html(imports: String) -> String {
        let files = [
            GeneratedFile(path: "theme.css", content: ":root {}"),
            GeneratedFile(path: "components/Card.tsx", content: "\(imports)\n\nexport function Card() {\n  return <div />;\n}\n"),
        ]
        return ReactHarnessBuilder.buildHTML(
            from: files, componentName: "Card", viewportWidth: 100,
            iconFontRelativePath: "icons", iconFontDir: iconFontDir
        )
    }

    /// The JavaScript string escape of `codepoint`, as the stubs write it.
    private static func glyph(_ codepoint: UInt32) -> String {
        "\\u{\(String(codepoint, radix: 16, uppercase: true))}"
    }

    @Test("Each family used gets a face for its bundled font, and no other family does")
    func facePerFamily() {
        let page = Self.html(imports: """
        import { VpnLock } from "@nine-thirty-five/material-symbols-react/outlined";
        import { Bell } from "react-feather";
        """)
        #expect(page.contains("font-family: 'Material Symbols Outlined';"))
        #expect(page.contains("url('icons/MaterialSymbolsOutlined.ttf')"))
        #expect(page.contains("font-family: 'feather';"))
        #expect(page.contains("url('icons/feather.ttf')"))
        #expect(!page.contains("url('icons/lucide.ttf')"))
        #expect(!page.contains("MaterialSymbolsRounded.ttf"))
    }

    @Test("A stub draws its own family's codepoint for the icon the component name stands for", arguments: [
        ("import { VpnLock } from \"@nine-thirty-five/material-symbols-react/rounded\";", "VpnLock", "Material Symbols Rounded", "vpn_lock"),
        ("import { Bell } from \"react-feather\";", "Bell", "feather", "bell"),
        ("import { Bell } from \"lucide-react\";", "Bell", "lucide", "bell"),
        ("import { BellIcon } from \"@phosphor-icons/react\";", "BellIcon", "phosphor", "bell"),
    ])
    func stubGlyph(imports: String, local: String, family: String, icon: String) throws {
        let codepoint = try #require(PenIconFontRegistry.shared.codepoint(family: family, name: icon))
        let page = Self.html(imports: imports)
        let stub = try #require(page.split(separator: "\n").first { $0.hasPrefix("const \(local) = ") }, "\(page)")
        #expect(stub.contains("\"\(family)\""), "\(stub)")
        #expect(stub.contains(Self.glyph(codepoint)), "\(stub)")
    }

    @Test("An aliased import is stubbed under its local name with the imported icon's glyph")
    func aliasedImport() throws {
        let page = Self.html(imports: """
        import { VpnLock } from "@nine-thirty-five/material-symbols-react/outlined";
        import { VpnLock as VpnLockSharp } from "@nine-thirty-five/material-symbols-react/sharp";
        """)
        let codepoint = try #require(PenIconFontRegistry.shared.codepoint(family: "Material Symbols Sharp", name: "vpn_lock"))
        let stub = try #require(page.split(separator: "\n").first { $0.hasPrefix("const VpnLockSharp = ") }, "\(page)")
        #expect(stub.contains("\"Material Symbols Sharp\""), "\(stub)")
        #expect(stub.contains(Self.glyph(codepoint)), "\(stub)")
        #expect(page.contains("const VpnLock = "))
    }

    @Test("A Phosphor stub carries each weight's glyph, as the package draws its weight prop")
    func phosphorWeights() throws {
        let page = Self.html(imports: "import { ChatDotsIcon } from \"@phosphor-icons/react\";")
        let stub = try #require(page.split(separator: "\n").first { $0.hasPrefix("const ChatDotsIcon = ") }, "\(page)")
        for (weight, name) in [("regular", "chat-dots"), ("thin", "chat-dots-thin"), ("bold", "chat-dots-bold")] {
            let codepoint = try #require(PenIconFontRegistry.shared.codepoint(family: "phosphor", name: name))
            #expect(stub.contains("\(weight): \"\(Self.glyph(codepoint))\""), "\(weight): \(stub)")
        }
    }

    /// The package takes its weight from the import path, the bare path being 400, so a
    /// stub draws the weight its path names, as the package's own glyphs would be.
    @Test("A Material stub draws the weight its import path names", arguments: [
        ("/outlined/200", "VpnLock", 200), ("/rounded/700", "VpnLock", 700), ("/sharp", "VpnLock", 400),
    ])
    func materialWeightFromPath(suffix: String, local: String, weight: Int) throws {
        let page = Self.html(imports: "import { \(local) } from \"@nine-thirty-five/material-symbols-react\(suffix)\";")
        let stub = try #require(page.split(separator: "\n").first { $0.hasPrefix("const \(local) = ") }, "\(page)")
        #expect(stub.contains("\"'wght' \(weight)\""), "\(stub)")
    }

    @Test("Two weights of one icon are two stubs, each at its own weight")
    func materialTwoWeights() throws {
        let page = Self.html(imports: """
        import { VpnLock } from "@nine-thirty-five/material-symbols-react/outlined/200";
        import { VpnLock as VpnLock700 } from "@nine-thirty-five/material-symbols-react/outlined/700";
        """)
        let light = try #require(page.split(separator: "\n").first { $0.hasPrefix("const VpnLock = ") }, "\(page)")
        let bold = try #require(page.split(separator: "\n").first { $0.hasPrefix("const VpnLock700 = ") }, "\(page)")
        #expect(light.contains("\"'wght' 200\""), "\(light)")
        #expect(bold.contains("\"'wght' 700\""), "\(bold)")
    }

    /// Green on its first run: a guard on what the change must leave alone.
    @Test("A stub of a family with no weight axis sets no variation")
    func noVariationElsewhere() throws {
        let page = Self.html(imports: "import { Bell } from \"react-feather\";")
        let stub = try #require(page.split(separator: "\n").first { $0.hasPrefix("const Bell = ") }, "\(page)")
        #expect(!stub.contains("wght"), "\(stub)")
    }

    /// WebKit sets a variable font at the optical size of its point size; the CG renderer,
    /// like Pen, draws the default cut (`parser-icon-font`'s 48 pt Material
    /// Symbols measured 4.482 at WebKit's, 2.953 at the default).
    @Test("A stub draws its glyph at the font's default optical size")
    func defaultOpticalSize() {
        let page = Self.html(imports: "import { VpnLock } from \"@nine-thirty-five/material-symbols-react/outlined\";")
        #expect(page.contains("fontOpticalSizing: \"none\""))
    }
}
