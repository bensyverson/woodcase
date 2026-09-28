//
//  IconLibraryMappingTests.swift
//  WoodcaseTests
//

import Testing
@testable import Woodcase

@Suite("IconLibraryMapping")
struct IconLibraryMappingTests {
    // MARK: - Lucide

    @Test("Lucide: arrow-left → ArrowLeft, package lucide-react")
    func lucideArrowLeft() {
        let result = IconLibraryMapping.resolve(family: "lucide", iconName: "arrow-left")
        #expect(result?.componentName == "ArrowLeft")
        #expect(result?.npmPackage == "lucide-react")
        #expect(result?.importPath == "lucide-react")
        #expect(result?.extraProps.isEmpty == true)
    }

    // MARK: - Feather

    @Test("Feather: bell → Bell, package react-feather")
    func featherBell() {
        let result = IconLibraryMapping.resolve(family: "feather", iconName: "bell")
        #expect(result?.componentName == "Bell")
        #expect(result?.npmPackage == "react-feather")
        #expect(result?.importPath == "react-feather")
    }

    // MARK: - Phosphor

    @Test("Phosphor: chat-dots → ChatDotsIcon, no weight prop")
    func phosphorChatDots() {
        let result = IconLibraryMapping.resolve(family: "phosphor", iconName: "chat-dots")
        #expect(result?.componentName == "ChatDotsIcon")
        #expect(result?.npmPackage == "@phosphor-icons/react")
        #expect(result?.importPath == "@phosphor-icons/react")
        #expect(result?.extraProps.isEmpty == true)
    }

    @Test("Phosphor: chat-dots-bold → ChatDotsIcon, weight bold")
    func phosphorChatDotsBold() {
        let result = IconLibraryMapping.resolve(family: "phosphor", iconName: "chat-dots-bold")
        #expect(result?.componentName == "ChatDotsIcon")
        #expect(result?.extraProps["weight"] == "bold")
    }

    @Test("Phosphor: heart-fill → HeartIcon, weight fill")
    func phosphorHeartFill() {
        let result = IconLibraryMapping.resolve(family: "phosphor", iconName: "heart-fill")
        #expect(result?.componentName == "HeartIcon")
        #expect(result?.extraProps["weight"] == "fill")
    }

    // MARK: - Material Symbols

    /// The path carries Pen's default weight, 200, since leaf AyTAji (`ReactEmitterMaterialWeightTests`).
    @Test("Material Outlined: vpn_lock → VpnLock, import path .../outlined/200")
    func materialOutlinedVpnLock() {
        let result = IconLibraryMapping.resolve(family: "Material Symbols Outlined", iconName: "vpn_lock")
        #expect(result?.componentName == "VpnLock")
        #expect(result?.npmPackage == "@nine-thirty-five/material-symbols-react")
        #expect(result?.importPath == "@nine-thirty-five/material-symbols-react/outlined/200")
    }

    @Test("Material: vpn-lock (hyphenated) → VpnLock (normalized)")
    func materialHyphenatedName() {
        let result = IconLibraryMapping.resolve(family: "Material Symbols Rounded", iconName: "vpn-lock")
        #expect(result?.componentName == "VpnLock")
        #expect(result?.importPath == "@nine-thirty-five/material-symbols-react/rounded/200")
    }

    @Test("Material: 18_up_rating → EighteenUpRating (digit conversion)")
    func materialLeadingDigits() {
        let result = IconLibraryMapping.resolve(family: "Material Symbols Outlined", iconName: "18_up_rating")
        #expect(result?.componentName == "EighteenUpRating")
    }

    @Test("Material Symbols Sharp uses .../sharp/200 import path")
    func materialSharp() {
        let result = IconLibraryMapping.resolve(family: "Material Symbols Sharp", iconName: "home")
        #expect(result?.componentName == "Home")
        #expect(result?.importPath == "@nine-thirty-five/material-symbols-react/sharp/200")
    }

    // MARK: - Unknown

    @Test("Unknown family returns nil")
    func unknownFamily() {
        let result = IconLibraryMapping.resolve(family: "ionicons", iconName: "home")
        #expect(result == nil)
    }

    // MARK: - Reverse lookup

    @Test("family(forImportPath:) recognizes all supported libraries")
    func reverseImportPathLookup() {
        #expect(IconLibraryMapping.family(forImportPath: "lucide-react") == "lucide")
        #expect(IconLibraryMapping.family(forImportPath: "react-feather") == "feather")
        #expect(IconLibraryMapping.family(forImportPath: "@phosphor-icons/react") == "phosphor")
        #expect(IconLibraryMapping.family(forImportPath: "@nine-thirty-five/material-symbols-react/outlined") == "Material Symbols Outlined")
        #expect(IconLibraryMapping.family(forImportPath: "@nine-thirty-five/material-symbols-react/rounded") == "Material Symbols Rounded")
        #expect(IconLibraryMapping.family(forImportPath: "@nine-thirty-five/material-symbols-react/sharp") == "Material Symbols Sharp")
        #expect(IconLibraryMapping.family(forImportPath: "unknown-package") == nil)
    }

    // MARK: - Number-to-words utility

    @Test("numberToWords handles key values for Material Symbols")
    func numberToWords() {
        #expect(IconLibraryMapping.numberToWords(0) == "Zero")
        #expect(IconLibraryMapping.numberToWords(1) == "One")
        #expect(IconLibraryMapping.numberToWords(10) == "Ten")
        #expect(IconLibraryMapping.numberToWords(18) == "Eighteen")
        #expect(IconLibraryMapping.numberToWords(21) == "TwentyOne")
        #expect(IconLibraryMapping.numberToWords(100) == "OneHundred")
        #expect(IconLibraryMapping.numberToWords(123) == "OneHundredTwentyThree")
        #expect(IconLibraryMapping.numberToWords(360) == "ThreeHundredSixty")
    }
}
