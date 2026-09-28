//
//  PenIconFontRegistryTests.swift
//  WoodcaseTests
//

import Testing
import Woodcase

struct PenIconFontRegistryTests {
    private let registry = PenIconFontRegistry.shared

    // MARK: - Codepoint Lookup

    @Test("Looks up known lucide icon codepoint")
    func lucideKnownIcon() throws {
        let cp = registry.codepoint(family: "lucide", name: "bell")
        #expect(cp != nil)
        #expect(try #require(cp) > 0)
    }

    @Test("Looks up known feather icon codepoint")
    func featherKnownIcon() {
        let cp = registry.codepoint(family: "feather", name: "bell")
        #expect(cp != nil)
    }

    @Test("Looks up known phosphor icon codepoint")
    func phosphorKnownIcon() {
        let cp = registry.codepoint(family: "phosphor", name: "chat-dots")
        #expect(cp != nil)
    }

    @Test("Phosphor weight variants have distinct codepoints")
    func phosphorWeightVariants() {
        let base = registry.codepoint(family: "phosphor", name: "chat-dots")
        let thin = registry.codepoint(family: "phosphor", name: "chat-dots-thin")
        #expect(base != nil)
        #expect(thin != nil)
        #expect(base != thin, "Weight variants should have different codepoints in Phosphor v1")
    }

    @Test("Looks up known Material Symbols icon codepoint")
    func materialSymbolsKnownIcon() {
        let cp = registry.codepoint(family: "Material Symbols Outlined", name: "vpn_lock")
        #expect(cp != nil)
    }

    @Test("All three Material Symbols variants share codepoints")
    func materialSymbolsSharedCodepoints() {
        let outlined = registry.codepoint(family: "Material Symbols Outlined", name: "home")
        let rounded = registry.codepoint(family: "Material Symbols Rounded", name: "home")
        let sharp = registry.codepoint(family: "Material Symbols Sharp", name: "home")
        #expect(outlined == rounded)
        #expect(rounded == sharp)
        #expect(outlined != nil)
    }

    @Test("Returns nil for unknown icon name")
    func unknownIconName() {
        let cp = registry.codepoint(family: "lucide", name: "nonexistent-icon-xyz")
        #expect(cp == nil)
    }

    @Test("Returns nil for unknown font family")
    func unknownFamily() {
        let cp = registry.codepoint(family: "unknown-family", name: "bell")
        #expect(cp == nil)
    }

    // MARK: - Font Name Mapping

    @Test("Returns correct CTFont family name for built-in families")
    func builtInFontNames() {
        #expect(registry.fontName(for: "lucide") == "lucide")
        #expect(registry.fontName(for: "feather") == "icomoon")
        #expect(registry.fontName(for: "phosphor") == "Phosphor")
        #expect(registry.fontName(for: "Material Symbols Outlined") == "Material Symbols Outlined")
    }

    @Test("Returns nil font name for unknown family")
    func unknownFamilyFontName() {
        #expect(registry.fontName(for: "nonexistent") == nil)
    }

    // MARK: - Names and Libraries

    @Test("names(in:) lists a bundled family's icon names, including a known one")
    func namesInBundledFamily() throws {
        let names = try #require(registry.names(in: "lucide"))
        #expect(names.contains("bell"))
        #expect(names.count > 1000)
    }

    @Test("names(in:) returns nil for a family that is registered nowhere")
    func namesInUnknownFamily() {
        #expect(registry.names(in: "not-a-real-family-xyz") == nil)
    }

    @Test("libraries lists at least the six bundled families")
    func librariesListsBundledFamilies() {
        let bundled: Set = [
            "lucide", "feather", "phosphor",
            "Material Symbols Outlined", "Material Symbols Rounded", "Material Symbols Sharp",
        ]
        #expect(bundled.isSubset(of: Set(registry.libraries)))
    }

    @Test("libraries is sorted")
    func librariesIsSorted() {
        // Read once: the shared registry takes custom families from concurrent tests, so
        // two reads can straddle a registration.
        let libraries = registry.libraries
        #expect(libraries == libraries.sorted())
    }

    // MARK: - Custom Registration

    @Test("Registers and looks up custom icon font family")
    func customRegistration() {
        let customMapping: [String: UInt32] = [
            "custom-icon": 0xE001,
            "another-icon": 0xE002,
        ]
        registry.register(family: "my-icons", fontName: "MyIconFont", mapping: customMapping)

        #expect(registry.codepoint(family: "my-icons", name: "custom-icon") == 0xE001)
        #expect(registry.codepoint(family: "my-icons", name: "another-icon") == 0xE002)
        #expect(registry.codepoint(family: "my-icons", name: "unknown") == nil)
        #expect(registry.fontName(for: "my-icons") == "MyIconFont")
    }

    // MARK: - Placeholder Fallback

    @Test("Placeholder for lucide is circle-question-mark")
    func lucidePlaceholder() throws {
        let placeholder = try #require(registry.placeholder(family: "lucide"))
        #expect(placeholder.codepoint == registry.codepoint(family: "lucide", name: "circle-question-mark"))
        #expect(placeholder.ctFontName == "lucide")
    }

    @Test("Placeholder for feather is help-circle")
    func featherPlaceholder() throws {
        let placeholder = try #require(registry.placeholder(family: "feather"))
        #expect(placeholder.codepoint == registry.codepoint(family: "feather", name: "help-circle"))
        #expect(placeholder.ctFontName == "icomoon")
    }

    @Test("Placeholder for phosphor is question")
    func phosphorPlaceholder() throws {
        let placeholder = try #require(registry.placeholder(family: "phosphor"))
        #expect(placeholder.codepoint == registry.codepoint(family: "phosphor", name: "question"))
        #expect(placeholder.ctFontName == "Phosphor")
    }

    @Test("Placeholder for each Material Symbols variant is help")
    func materialSymbolsPlaceholder() throws {
        for family in ["Material Symbols Outlined", "Material Symbols Rounded", "Material Symbols Sharp"] {
            let placeholder = try #require(registry.placeholder(family: family), "family: \(family)")
            #expect(
                placeholder.codepoint == registry.codepoint(family: family, name: "help"),
                "family: \(family)"
            )
            #expect(placeholder.ctFontName == family, "family: \(family)")
        }
    }

    @Test("Placeholder is nil for an unknown family")
    func placeholderUnknownFamily() {
        #expect(registry.placeholder(family: "not-a-real-family-xyz") == nil)
    }

    @Test("Placeholder is nil for a custom-registered family with no bundled placeholder")
    func placeholderCustomFamily() {
        registry.register(
            family: "my-placeholder-less-icons",
            fontName: "MyIconFont",
            mapping: ["custom-icon": 0xE001]
        )
        #expect(registry.placeholder(family: "my-placeholder-less-icons") == nil)
    }
}
