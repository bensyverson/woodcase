import CoreText
import Foundation
import os
import Woodcase

/// Registers test fonts bundled in `Tests/WoodcaseTests/Fonts/` with Core Text
/// so they are available process-wide without system installation.
///
/// Registration uses `.process` scope and is guarded to run only once per process.
/// Calling ``registerTestFonts()`` multiple times is safe and idempotent.
///
/// Inter is here because it is Pen's default face and most rendered fixtures set it:
/// without it the renderer draws them in SF Pro and a snapshot gate measures the
/// fallback, not the renderer. It is the same variable file the Google Fonts resolver
/// downloads, committed so no test reads the user's `~/.woodcase` cache. Registration
/// cannot be undone, so once any test in this process calls ``registerTestFonts()``,
/// every later test sees Inter: a suite whose result depends on Inter must call it
/// itself rather than rely on the order suites run in.
///
/// IBM Plex Sans is Google's variable face as fonts.gstatic.com serves it (v23), the file
/// Pen's own font table names — not the static cuts, whose outlines are an older release
/// (`project/2026-09-28-pen-font-faces.md`).
///
/// Woodcase Static Sans is a static family with a cut at 400, 500, 600 and 700, made from
/// Inter by `scripts/gen-static-test-family.py`; no fixture sets it, and
/// `PenFaceMatchingTests` checks each weight resolves to the cut CSS picks.
enum TestFontRegistration {
    private static let fontsDir = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fonts")

    private static let once: Void = {
        let fontFiles = [
            "IBMPlexSans[wdth,wght].ttf",
            "Inter[opsz,wght].ttf",
            "StaticSans/WoodcaseStaticSans-Regular.ttf",
            "StaticSans/WoodcaseStaticSans-Medium.ttf",
            "StaticSans/WoodcaseStaticSans-SemiBold.ttf",
            "StaticSans/WoodcaseStaticSans-Bold.ttf",
        ]

        for file in fontFiles {
            let url = fontsDir.appendingPathComponent(file)
            var error: Unmanaged<CFError>?
            let success = CTFontManagerRegisterFontsForURL(
                url as CFURL,
                .process,
                &error
            )
            if !success {
                let desc = error?.takeRetainedValue().localizedDescription ?? "unknown"
                print("Warning: Failed to register font \(file): \(desc)")
            }
        }

        waitUntilMatchable(["Inter", "IBM Plex Sans", "Woodcase Static Sans"])

        // Any font resolution cached before this point predates these faces.
        PenFontRegistry.didRegisterFonts()
    }()

    /// Blocks until Core Text matches each family by name, for at most ten seconds.
    ///
    /// Once, on the first run after a build, three React emitter tests asked for Inter
    /// straight after registering it, were answered with the fallback, and emitted
    /// `lineHeight: normal` where the next six runs emitted Inter's pitch (leaf 3Xbv46,
    /// 2026-09-27). The likeliest reading — unproven — is that registration returns before
    /// every thread's font matching sees the faces; waiting here costs nothing when they
    /// already match, and guarantees every caller of ``registerTestFonts()`` sees them.
    private static func waitUntilMatchable(_ families: [String]) {
        let deadline = Date().addingTimeInterval(10)
        for family in families {
            while !matches(family), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }

    /// Whether a descriptor naming `family` resolves to that family.
    private static func matches(_ family: String) -> Bool {
        let descriptor = CTFontDescriptorCreateWithAttributes([kCTFontFamilyNameAttribute: family] as CFDictionary)
        let font = CTFontCreateWithFontDescriptor(descriptor, 12, nil)
        return (CTFontCopyFamilyName(font) as String).caseInsensitiveCompare(family) == .orderedSame
    }

    /// Registers IBM Plex Sans and Inter from the Fonts directory with Core Text.
    ///
    /// JetBrains Mono and its renamed copies there are left alone: their tests own the
    /// moment those families appear.
    ///
    /// After calling this, "IBM Plex Sans" and "Inter" become
    /// available to `CTFontCreateWithFontDescriptor` and `PenTextMeasurer`.
    static func registerTestFonts() {
        _ = once
    }
}
