//
//  GoogleFontResolver.swift
//  Woodcase
//

import CoreGraphics
import CoreText
import Foundation
import os

/// Resolves the font faces a document draws to downloaded and registered font files.
///
/// The unit is the face — family, weight and style (``PenFontFace``) — because a family
/// is not one file: a static family ships a file per face, a variable one a file per
/// style. For each face the resolver follows this chain:
/// 1. **Registered** — if Core Text already has a font of the family in that style and
///    weight, or the operating system ships the family, skip.
/// 2. **On-disk cache** — register every file cached for the family.
/// 3. **GitHub download** — fetch the file the family's METADATA.pb names for the face
///    (``GoogleFontMetadata/entry(weight:style:)``) from the
///    [google/fonts](https://github.com/google/fonts) repository, caching the METADATA
///    beside it so the next run can answer from disk.
///
/// ## Usage
///
/// Call ``prepareFonts(for:)`` before rendering to ensure all fonts in a
/// document are available:
///
/// ```swift
/// await GoogleFontResolver.shared.prepareFonts(for: document)
/// ```
///
/// If `prepareFonts` is skipped or a font cannot be resolved, the rendering
/// pipeline falls back to SF Pro (the default behavior).
///
/// ## Reads take the offline half
///
/// ``prepareCachedFonts(for:diagnostics:)`` is the same chain with step 3 removed: it
/// registers what the system and the disk cache already hold and reports what it
/// cannot, without a network call. ``SettledTree`` runs it before every layout, so
/// `tree`, `lint` and the write verbs measure in the same faces `shot` and `render`
/// draw with — the registration that used to happen only inside ``resolve(_:)`` is why
/// the two disagreed about text widths.
///
/// ## Organization
///
/// The type is split across files by seam, all in this folder: this file holds the
/// class itself and the document entry points (``prepareFonts(for:)`` and
/// ``prepareCachedFonts(for:diagnostics:)``); `GoogleFontResolver+Faces.swift` holds
/// ``resolve(_:)`` and the per-face fetch; `GoogleFontResolver+Registration.swift`
/// holds cache lookup and CoreText registration; `GoogleFontResolver+Fallback.swift`
/// holds the fallback messages and where they get reported; `GoogleFontResolver+Metadata.swift`
/// holds the GitHub METADATA.pb fetch; `GoogleFontResolver+FamilyCollection.swift` holds
/// the document-tree walk that finds the faces a document draws. `cache`, `fetcher` and `state`
/// are `internal` rather than `private` because every one of those files reads them.
public final class GoogleFontResolver: Sendable {
    /// Shared singleton using `$WOODCASE_HOME/fonts` and ``StandardDataFetcher``.
    public static let shared = GoogleFontResolver(
        cache: GoogleFontCache(),
        fetcher: StandardDataFetcher.make()
    )

    /// The license directories to probe in order.
    static let licenseDirectories = ["ofl", "apache", "ufl"]

    /// Base URL for raw file access to the google/fonts repository.
    static let githubBaseURL = "https://raw.githubusercontent.com/google/fonts/main"

    let cache: GoogleFontCache
    let fetcher: RemoteDataFetching

    struct State {
        /// Faces ``resolve(_:)`` has resolved (or attempted) this session.
        var attemptedFaces: Set<PenFontFace> = []

        /// Cache files this resolver has handed to Core Text, so none is registered twice.
        var registeredFiles: Set<URL> = []

        /// The scratch copy each memory-only cache file was registered from, by
        /// `<family directory>/<file name>`.
        var stagedMemoryFiles: [String: URL] = [:]

        /// How many times ``logCacheFallbackOnce()`` has actually printed its line.
        /// Checked and incremented together so two concurrent downloads that both
        /// fail to cache still print the line once, not twice.
        var cacheFallbackNoticeCount = 0

        /// Families ``resolveFromCache(family:faces:)`` has confirmed Core Text resolves.
        ///
        /// Registration is process-scoped and nothing ever unregisters, so a family
        /// that was placed once stays placed — and asking again costs a blocking XPC
        /// round trip to `fontd` (see ``FontRegistryGate``). A read settles a document
        /// on every invocation, and the viewer settles one on every edit, so this is
        /// the difference between one probe per family and one per settle. Misses are
        /// deliberately not remembered: a `render` may place the family at any moment.
        var placedFamilies: Set<String> = []

        /// Faces whose family ``resolveFromCache(family:faces:)`` placed after offering
        /// them everything the cache holds — so a settle does not list the cache again
        /// for a face it already tried.
        var offlineFaces: Set<PenFontFace> = []

        /// Families this resolver has already written a fallback line to standard
        /// error about, so a document naming one font in forty text nodes — or a
        /// long-lived process settling the same document again — says it once.
        var reportedFallbacks: Set<String> = []

        /// Why each family's download failed, for the fallback warning. A family that
        /// resolved, or that was never downloaded, has no entry.
        var downloadFailures: [String: GoogleFontError] = [:]
    }

    let state = OSAllocatedUnfairLock(initialState: State())

    /// Creates a resolver with the given cache and fetcher.
    ///
    /// - Parameters:
    ///   - cache: The on-disk font cache.
    ///   - fetcher: The network fetcher (injectable for testing).
    public init(cache: GoogleFontCache, fetcher: RemoteDataFetching) {
        self.cache = cache
        self.fetcher = fetcher
    }

    // MARK: - Public API

    /// Downloads and registers any missing Google Fonts faces the document draws.
    ///
    /// Walks the document tree to collect every face (family, weight, style) its text
    /// sets, then resolves each family's faces (``resolve(_:)``) — families
    /// concurrently. A family the document declares (``PenDocument/fonts``) and Core
    /// Text already resolves is the document's own, and is left alone.
    ///
    /// This is a best-effort operation: a font that cannot be resolved falls back to
    /// SF Pro during rendering, and the fallback is reported once per family — saying
    /// whether Google Fonts has no such family or the download could not happen, and why.
    ///
    /// - Parameter document: The parsed document to scan for font references.
    public func prepareFonts(for document: PenDocument) async {
        await prepareFonts(for: document, diagnostics: nil)
    }

    /// Prepares fonts for a document, optionally reporting issues to a diagnostic collector.
    public func prepareFonts(
        for document: PenDocument,
        diagnostics: PenDiagnosticCollector?
    ) async {
        let declared = Set((document.fonts ?? []).map(\.name)).filter(PenTextMeasurer.fontFamilyAvailable)
        let families = Dictionary(grouping: Self.collectFontFaces(from: document), by: \.family)
            .filter { !declared.contains($0.key) }

        await withTaskGroup(of: String.self) { group in
            for (family, faces) in families {
                group.addTask {
                    await self.resolve(family: family, faces: Set(faces))
                    return family
                }
            }
            for await family in group where !PenTextMeasurer.fontFamilyAvailable(family) {
                reportFallback(
                    family: family,
                    message: downloadFailureMessage(for: family),
                    diagnostics: diagnostics
                )
            }
        }
    }

    /// Registers the fonts a document names that this machine already has, and reports
    /// the ones it does not — without touching the network.
    ///
    /// This is the *read* verbs' font path. `shot` and `render` may go to GitHub for a
    /// face they have never seen, because they are about to draw it; a read may not.
    /// A read that downloaded a font would be a read that hangs behind a captive
    /// portal, and `lint` promises in its own help that it stays offline. So this takes
    /// the system faces and the on-disk cache and stops.
    ///
    /// It still matters that it runs. Registration happens inside ``resolve(_:)``,
    /// so a font sitting in the cache is invisible to Core Text until something asks
    /// for it — which is why `tree` used to measure a cached Google font in SF Pro
    /// while `shot` measured it in the real face, and the two disagreed about every
    /// text width. ``SettledTree`` calls this before it lays a document out, so every
    /// verb that settles measures in the face the render will use.
    ///
    /// What it cannot resolve it says, rather than quietly reporting a width in a face
    /// the render will not use: one warning per family, to `diagnostics` when a
    /// collector is given and to standard error when it is not — never both, so a
    /// caller that collects decides for itself when and how to print.
    ///
    /// - Parameters:
    ///   - document: The document to scan, after expansion and variable resolution —
    ///     a font family written as a `$variable` is only a literal by then.
    ///   - diagnostics: Where to report a family that stays unresolved. `nil` sends the
    ///     warning to standard error instead.
    /// - Returns: The families that are still unavailable, sorted, so a caller can
    ///   label its own output without capturing the warning.
    @discardableResult
    public func prepareCachedFonts(
        for document: PenDocument,
        diagnostics: PenDiagnosticCollector? = nil
    ) -> [String] {
        var unresolved: [String] = []
        let families = Dictionary(grouping: Self.collectFontFaces(from: document), by: \.family)
        for (family, faces) in families.sorted(by: { $0.key < $1.key })
            where !resolveFromCache(family: family, faces: Set(faces))
        {
            unresolved.append(family)
            reportFallback(
                family: family,
                message: fallbackMessage(for: family),
                diagnostics: diagnostics
            )
        }
        return unresolved
    }

    /// How many families this resolver has written a fallback line to standard error
    /// about.
    ///
    /// Not `private`, so a test can confirm the no-collector path reports without
    /// capturing the process's real standard error — the same arrangement
    /// ``cacheFallbackNoticeCount`` uses for its own notice.
    var fallbackNoticeCount: Int {
        state.withLock { $0.reportedFallbacks.count }
    }
}
