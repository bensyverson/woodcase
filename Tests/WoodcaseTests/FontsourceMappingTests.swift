//
//  FontsourceMappingTests.swift
//  WoodcaseTests
//

import Testing
@testable import Woodcase

@Suite("FontsourceMapping")
struct FontsourceMappingTests {
    @Test("IBM Plex Sans → @fontsource/ibm-plex-sans")
    func ibmPlexSans() {
        let result = FontsourceMapping.packageName(for: "IBM Plex Sans")
        #expect(result == "@fontsource/ibm-plex-sans")
    }

    @Test("Inter → @fontsource/inter")
    func inter() {
        let result = FontsourceMapping.packageName(for: "Inter")
        #expect(result == "@fontsource/inter")
    }

    @Test("CSS import format is correct")
    func cssImport() {
        let result = FontsourceMapping.cssImport(for: "IBM Plex Sans")
        #expect(result == "@import \"@fontsource/ibm-plex-sans\";")
    }

    @Test("Roboto Mono → @fontsource/roboto-mono")
    func robotoMono() {
        let result = FontsourceMapping.packageName(for: "Roboto Mono")
        #expect(result == "@fontsource/roboto-mono")
    }
}
