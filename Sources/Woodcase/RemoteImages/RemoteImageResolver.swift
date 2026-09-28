//
//  RemoteImageResolver.swift
//  Woodcase
//

import CoreGraphics
import Foundation
import ImageIO
import os

/// Downloads the images an `http(s)` image fill points at, and serves them back to the
/// renderer from a disk cache.
///
/// The renderer's ``PenRenderer/ImageProvider`` is synchronous, so the network cannot
/// happen inside it. Resolution is therefore two steps, exactly like Google Fonts:
///
/// 1. **Prepare** — ``prepareImages(for:)``, once, before layout and render. It walks
///    the document, collects every remote image-fill URL, and downloads what the cache
///    does not already hold.
/// 2. **Serve** — ``cachedImage(for:)``, synchronously, from inside the provider.
///
/// ## Usage
///
/// ```swift
/// await RemoteImageResolver.shared.prepareImages(for: document)
/// let image = PenRenderer.render(
///     document, layoutRects: rects, size: size,
///     imageProvider: PenRenderer.imageProvider(relativeTo: penFileDirectory)
/// )
/// ```
///
/// Skipping the prepare step is not an error: an image that is not cached simply is not
/// drawn, the same as a missing file on disk.
public final class RemoteImageResolver: Sendable {
    /// Shared singleton using `$WOODCASE_HOME/images` and ``StandardDataFetcher``.
    public static let shared = RemoteImageResolver(
        cache: RemoteImageCache(),
        fetcher: StandardDataFetcher.make()
    )

    private let cache: RemoteImageCache
    private let fetcher: RemoteDataFetching

    private struct State {
        /// URLs this resolver has already tried to download and failed on. A miss is
        /// remembered so a document with a dead URL is not re-fetched on every render;
        /// a *success* needs no entry, because the cache itself is the memory.
        var failedURLs: Set<String> = []

        /// How many times ``logCacheFallbackOnce()`` has actually printed its line.
        var cacheFallbackNoticeCount = 0

        /// Why each URL's download failed, for the warning. A URL that resolved, or
        /// that was never fetched, has no entry.
        var downloadFailures: [String: RemoteFetchError] = [:]
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// Creates a resolver with the given cache and fetcher.
    ///
    /// - Parameters:
    ///   - cache: The on-disk image cache.
    ///   - fetcher: The network fetcher (injectable for testing).
    public init(cache: RemoteImageCache, fetcher: RemoteDataFetching) {
        self.cache = cache
        self.fetcher = fetcher
    }

    // MARK: - Public API

    /// Downloads any remote images referenced by the document that are not cached yet.
    ///
    /// - Parameter document: The document to scan for remote image fills.
    public func prepareImages(for document: PenDocument) async {
        await prepareImages(for: document, diagnostics: nil)
    }

    /// Prepares remote images, optionally reporting failures to a diagnostic collector.
    ///
    /// Downloads run concurrently and are best-effort: an image that cannot be fetched
    /// leaves its fill undrawn rather than failing the render.
    ///
    /// - Parameters:
    ///   - document: The document to scan for remote image fills.
    ///   - diagnostics: Collector for a warning per unresolvable image, or `nil`.
    public func prepareImages(
        for document: PenDocument,
        diagnostics: PenDiagnosticCollector?
    ) async {
        let urls = Self.collectRemoteImageURLs(from: document)
        guard !urls.isEmpty else { return }

        await withTaskGroup(of: (String, Data?).self) { group in
            for url in urls {
                group.addTask { await (url, self.resolve(urlString: url)) }
            }
            for await (url, data) in group where data == nil {
                diagnostics?.warn(downloadFailureMessage(for: url), stage: .imageResolution)
            }
        }
    }

    /// Resolves one remote image URL to its bytes, downloading it if the cache misses.
    ///
    /// - Parameter urlString: The image fill's URL, exactly as the .pen file spells it.
    /// - Returns: The image bytes, or `nil` if the URL is unusable or the fetch failed.
    public func resolve(urlString: String) async -> Data? {
        if let cached = cachedData(for: urlString) { return cached }

        let shouldFetch = state.withLock { !$0.failedURLs.contains(urlString) }
        guard shouldFetch, let url = URL(string: urlString) else { return nil }

        do {
            let data = try await fetcher.fetch(url: url)
            // Caching is best-effort. An unwritable cache directory — a read-only cache
            // volume, a sandboxed process — must not cost the render its image, so the
            // bytes go to an in-process store instead and the first such failure prints
            // one line.
            do {
                try cache.cache(data: data, for: urlString)
            } catch {
                RemoteImageMemoryFallback.store(
                    data, rootDirectory: cache.rootDirectory, urlString: urlString
                )
                logCacheFallbackOnce()
            }
            return data
        } catch {
            state.withLock {
                $0.failedURLs.insert(urlString)
                $0.downloadFailures[urlString] = Self.fetchFailure(error)
            }
            return nil
        }
    }

    /// The decoded image for a URL, if this resolver already has its bytes.
    ///
    /// Synchronous on purpose: this is what runs inside ``PenRenderer/ImageProvider``,
    /// where there is no `await` to be had. It never reaches the network — an image
    /// nobody prepared is simply absent.
    ///
    /// - Parameter urlString: The image fill's URL.
    /// - Returns: The decoded image, or `nil` if it is not cached or is not decodable.
    public func cachedImage(for urlString: String) -> CGImage? {
        if let fallback = RemoteImageMemoryFallback.data(
            rootDirectory: cache.rootDirectory, urlString: urlString
        ) {
            return Self.decode(fallback)
        }
        guard let source = CGImageSourceCreateWithURL(
            cache.imageFileURL(for: urlString) as CFURL, nil
        ) else {
            return nil
        }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// How many times this resolver has printed the cache-fallback notice — 0 or 1.
    ///
    /// Not `private`, so a test can confirm "once, never per image" without capturing
    /// real standard error.
    var cacheFallbackNoticeCount: Int {
        state.withLock { $0.cacheFallbackNoticeCount }
    }

    // MARK: - Private

    /// A fetch error as the typed transport error it should be.
    ///
    /// ``URLSessionDataFetcher`` only ever throws ``RemoteFetchError``; a custom fetcher
    /// may throw anything, and that is still a fetch that got no answer — the same
    /// fallback ``GoogleFontResolver`` uses for its own fetch failures.
    private static func fetchFailure(_ error: Error) -> RemoteFetchError {
        error as? RemoteFetchError
            ?? .unreachable(NetworkFailure(classifying: error, trustEvaluationCode: nil, proxy: nil))
    }

    /// What to say about a URL that could not be downloaded — why, not just that it
    /// failed.
    ///
    /// - Parameter urlString: The URL that stays unresolved.
    /// - Returns: The message, without a leading `woodcase: `.
    private func downloadFailureMessage(for urlString: String) -> String {
        guard let failure = state.withLock({ $0.downloadFailures[urlString] }) else {
            return "Image '\(urlString)' could not be fetched; the fill will not be drawn"
        }
        return "Image '\(urlString)' could not be downloaded: \(failure.reasonPhrase); "
            + "the fill will not be drawn"
    }

    /// The bytes for a URL from either cache, in-process store first — when it has an
    /// entry it is the only place the bytes live, the disk write having failed.
    private func cachedData(for urlString: String) -> Data? {
        RemoteImageMemoryFallback.data(rootDirectory: cache.rootDirectory, urlString: urlString)
            ?? cache.cachedImageData(for: urlString)
    }

    /// Decodes image bytes, or returns `nil` when they are not an image at all — an
    /// error page served with a 200, most often.
    private static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Prints, once per resolver, the notice that the on-disk image cache could not be
    /// written. Never once per image: a document with a dozen remote fills against the
    /// same unwritable directory would otherwise print the same line a dozen times.
    private func logCacheFallbackOnce() {
        let shouldLog = state.withLock { current -> Bool in
            guard current.cacheFallbackNoticeCount == 0 else { return false }
            current.cacheFallbackNoticeCount += 1
            return true
        }
        guard shouldLog else { return }
        StandardErrorLine.write("""
        woodcase: cannot write the image cache at \(cache.rootDirectory.path); holding \
        downloaded images in memory for this process instead.
        """)
    }
}
