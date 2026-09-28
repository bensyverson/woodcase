//
//  PenFontRegistrationCacheTests.swift
//  WoodcaseTests
//

import CoreText
import Foundation
import Testing
@testable import Woodcase

/// Tests that font resolution stays correct when a font is registered with
/// Core Text *after* a resolution for its family has already been cached.
///
/// `PenTextMeasurer.fontCache` is process-wide. Before this suite existed, a
/// lookup that ran before registration cached the SF Pro fallback under the
/// requested family's key and every later lookup returned the poisoned entry —
/// nondeterministic under parallel tests, and reachable in production through
/// `PenIconFontRegistry` and `GoogleFontResolver`, which both register fonts
/// lazily at runtime.
struct PenFontRegistrationCacheTests {
    private let size: Double = 16

    // MARK: - The memoization still memoizes

    @Test("A present family is still memoized across identical requests")
    func presentFamilyIsMemoized() {
        let generation = PenFontRegistry.generation
        let a = PenTextMeasurer.resolveFont(
            family: "Helvetica", size: 23, weight: "normal", style: "normal"
        )
        let b = PenTextMeasurer.resolveFont(
            family: "Helvetica", size: 23, weight: "normal", style: "normal"
        )

        // A concurrent registration legitimately flushes the cache between the
        // two calls; only assert identity when the registration state held.
        #expect(a === b || PenFontRegistry.generation != generation)
    }

    // MARK: - Registration invalidates

    @Test("Registering fonts drops cached resolutions")
    func registrationDropsCachedResolutions() {
        let key = FontResolutionCache.Key(
            family: "Helvetica", size: 21, weight: "normal", style: "normal"
        )
        let generation = PenFontRegistry.generation
        _ = PenTextMeasurer.resolveFont(
            family: "Helvetica", size: 21, weight: "normal", style: "normal"
        )
        #expect(
            PenTextMeasurer.fontCache.font(for: key) != nil
                || PenFontRegistry.generation != generation
        )

        PenFontRegistry.didRegisterFonts()

        #expect(PenTextMeasurer.fontCache.font(for: key) == nil)
    }

    @Test("Registering fonts advances the generation")
    func registrationAdvancesGeneration() {
        let before = PenFontRegistry.generation
        PenFontRegistry.didRegisterFonts()
        #expect(PenFontRegistry.generation > before)
    }

    @Test("A Core Text font-set change advances the generation without the hook")
    func coreTextNotificationAdvancesGeneration() {
        let before = PenFontRegistry.generation

        // Stands in for a registrar outside Woodcase that never calls
        // didRegisterFonts(): Core Text posts this whenever the font set
        // changes, and the observer must pick it up on its own.
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetLocalCenter(),
            CFNotificationName(kCTFontManagerRegisteredFontsChangedNotification),
            nil,
            nil,
            true
        )

        #expect(PenFontRegistry.generation > before)
    }

    // MARK: - End-to-end reproduction

    @Test("A family registered after a failed resolution then resolves to that family")
    func registrationAfterFallbackResolvesCorrectly() throws {
        let font = try RenamedFont.make()
        defer { font.tearDown() }

        try #require(
            !PenTextMeasurer.fontFamilyAvailable(font.family),
            "\(font.family) must not be installed for this test to mean anything"
        )

        // Resolve before registration: this necessarily falls back.
        let before = PenTextMeasurer.resolveFont(
            family: font.family, size: size, weight: "normal", style: "normal"
        )
        #expect(CTFontCopyFamilyName(before) as String != font.family)

        var error: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(font.url as CFURL, .process, &error)
        try #require(
            registered,
            "registration failed: \(error?.takeRetainedValue().localizedDescription ?? "unknown")"
        )
        PenFontRegistry.didRegisterFonts()

        // Resolve again: the registered family must win over the cached fallback.
        let after = PenTextMeasurer.resolveFont(
            family: font.family, size: size, weight: "normal", style: "normal"
        )
        #expect(CTFontCopyFamilyName(after) as String == font.family)
    }

    // MARK: - Test Font Fixture

    /// A private copy of a bundled test font whose family name has been
    /// rewritten, so that this suite is the only thing in the process that ever
    /// registers it and the "resolve before registration" ordering is exact.
    ///
    /// The rewrite substitutes equal-length ASCII, so every table offset in the
    /// TTF stays valid and only the family and PostScript names change.
    private struct RenamedFont {
        /// The rewritten family name, as Core Text will report it.
        let family: String
        /// Location of the rewritten TTF on disk.
        let url: URL

        private static let sourceFamily = "IBM Plex Sans"
        private static let renamedFamily = "Woodcase Font"
        private static let sourcePostScript = "IBMPlexSans"
        private static let renamedPostScript = "WoodcaseFnt"

        /// Writes a renamed copy of `IBMPlexSans[wdth,wght].ttf` to a temporary file.
        static func make() throws -> RenamedFont {
            let source = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .appendingPathComponent("Fonts")
                .appendingPathComponent("IBMPlexSans[wdth,wght].ttf")
            let sourceData = try Data(contentsOf: source)
            var bytes = [UInt8](sourceData)

            for (find, replace) in [
                (sourceFamily, renamedFamily),
                (sourcePostScript, renamedPostScript),
            ] {
                bytes = replacing(bytes, ascii(find), with: ascii(replace))
                bytes = replacing(bytes, utf16BE(find), with: utf16BE(replace))
            }

            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("woodcase-font-\(UUID().uuidString).ttf")
            try Data(bytes).write(to: url)
            return RenamedFont(family: renamedFamily, url: url)
        }

        /// Unregisters the font and deletes the temporary file.
        func tearDown() {
            CTFontManagerUnregisterFontsForURL(url as CFURL, .process, nil)
            PenFontRegistry.didRegisterFonts()
            try? FileManager.default.removeItem(at: url)
        }

        private static func ascii(_ string: String) -> [UInt8] {
            Array(string.utf8)
        }

        private static func utf16BE(_ string: String) -> [UInt8] {
            string.utf16.flatMap { [UInt8($0 >> 8), UInt8($0 & 0xFF)] }
        }

        /// Replaces every occurrence of `find` with `replace`, which must be the same length.
        private static func replacing(
            _ bytes: [UInt8],
            _ find: [UInt8],
            with replace: [UInt8]
        ) -> [UInt8] {
            precondition(find.count == replace.count, "replacement must not move table offsets")
            guard !find.isEmpty, bytes.count >= find.count else { return bytes }

            var output = bytes
            var index = 0
            while index <= output.count - find.count {
                if Array(output[index ..< index + find.count]) == find {
                    output.replaceSubrange(index ..< index + find.count, with: replace)
                    index += find.count
                } else {
                    index += 1
                }
            }
            return output
        }
    }
}
