//
//  FigmaImageFetcher.swift
//  Woodcase
//

import CryptoKit
import Foundation

/// Downloads the images a Figma clipboard names by hash.
///
/// The clipboard carries no image bytes: figmeta's `imageHashes`
/// (``FigmaClipboardMetadata/imageHashes``) maps each image's hash to a signed URL its
/// bytes can be fetched from. This fetches them and checks each against its hash, which is
/// the SHA-1 of the bytes. It writes nothing: the caller stores the bytes where its
/// document can reach them and names that place in ``FigmaImportOptions/imageURLs``, or
/// swaps a failed image's fill for ``FigmaImagePlaceholder``.
///
/// Make one and keep it — per paste, or for the app's life. Every fetch through it, by
/// ``fetch(hash:url:)`` one image at a time or by ``fetch(_:)`` for a whole clipboard,
/// shares its bound of ``maximumConcurrentFetches`` in flight, each within ``timeout``.
/// The network goes through one ``RemoteDataFetching``, so tests inject one and never reach
/// it; the default's `URLSession`s are shared process-wide by route
/// (``URLSessionDataFetcher``), so connections pool however many fetchers are made.
public final class FigmaImageFetcher: Sendable {
    /// The bytes of one image, and the format they are in.
    public struct FetchedImage: Friendly {
        /// The image file's bytes.
        public var data: Data
        /// Their format, sniffed from the leading bytes.
        public var format: ImageFileFormat

        /// An image of `data` in `format`.
        ///
        /// - Parameters:
        ///   - data: The image file's bytes.
        ///   - format: Their format.
        public init(data: Data, format: ImageFileFormat) {
            self.data = data
            self.format = format
        }
    }

    /// How many downloads run at once unless told otherwise.
    public static let defaultMaximumConcurrentFetches = 4
    /// How long one download may take unless told otherwise: shorter than a fetcher's own
    /// minute, because a paste is waiting on it.
    public static let defaultTimeout: Duration = .seconds(30)

    /// What downloads each URL.
    public let fetcher: any RemoteDataFetching
    /// How long one download may take, start to finish, not counting the wait for a slot.
    public let timeout: Duration
    /// How many downloads run at once, across every call; at least one.
    public var maximumConcurrentFetches: Int {
        slots.limit
    }

    /// The slots every call's downloads share.
    private let slots: FetchSlots

    /// A fetcher.
    ///
    /// - Parameters:
    ///   - fetcher: What downloads each URL; ``StandardDataFetcher/make(environment:)`` by
    ///     default.
    ///   - maximumConcurrentFetches: How many downloads run at once across every call; a
    ///     value below one means one.
    ///   - timeout: How long one download may take.
    public init(
        fetcher: any RemoteDataFetching = StandardDataFetcher.make(),
        maximumConcurrentFetches: Int = defaultMaximumConcurrentFetches,
        timeout: Duration = defaultTimeout
    ) {
        self.fetcher = fetcher
        self.timeout = timeout
        slots = FetchSlots(limit: maximumConcurrentFetches)
    }

    /// Downloads one image, waiting for a slot first if the bound is reached.
    ///
    /// - Parameters:
    ///   - hash: The image's hash, as lowercase hex.
    ///   - url: The URL figmeta names for it.
    /// - Returns: Its bytes and format, or why they could not be had —
    ///   ``FigmaImageFetchError/cancelled`` when the calling task was canceled first.
    public func fetch(hash: String, url: String) async -> Result<FetchedImage, FigmaImageFetchError> {
        guard let location = URL(string: url), location.scheme?.lowercased() == "https", location.host() != nil else {
            return .failure(.invalidURL(url))
        }
        do {
            try await slots.acquire()
        } catch {
            return .failure(.cancelled)
        }
        let downloaded: Result<Data?, any Error>
        do {
            downloaded = try await .success(download(location))
        } catch {
            downloaded = .failure(error)
        }
        await slots.release()
        let data: Data
        switch downloaded {
        case let .success(fetched?):
            data = fetched
        case .success(nil):
            return .failure(.timedOut)
        case let .failure(error as RemoteFetchError):
            return .failure(.fetchFailed(error))
        case let .failure(error):
            if Task.isCancelled { return .failure(.cancelled) }
            let failure = NetworkFailure(classifying: error, trustEvaluationCode: nil, proxy: nil)
            return .failure(.fetchFailed(.unreachable(failure)))
        }
        let actual = Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard actual == hash.lowercased() else { return .failure(.hashMismatch(actual: actual)) }
        guard let format = ImageFileFormat(sniffing: data) else { return .failure(.unrecognizedFormat) }
        return .success(FetchedImage(data: data, format: format))
    }

    /// Downloads every image figmeta names, within the fetcher's bound.
    ///
    /// - Parameter imageHashes: Each image's hash, as lowercase hex, mapped to the URL its
    ///   bytes can be fetched from — ``FigmaClipboardMetadata/imageHashes``.
    /// - Returns: For each hash, its bytes and format, or why they could not be had.
    public func fetch(_ imageHashes: [String: String]) async -> [String: Result<FetchedImage, FigmaImageFetchError>] {
        await withTaskGroup(of: (String, Result<FetchedImage, FigmaImageFetchError>).self) { group in
            for (hash, url) in imageHashes.sorted(by: { $0.key < $1.key }) {
                group.addTask { await (hash, self.fetch(hash: hash, url: url)) }
            }
            var results: [String: Result<FetchedImage, FigmaImageFetchError>] = [:]
            for await (hash, result) in group {
                results[hash] = result
            }
            return results
        }
    }

    /// The URL's bytes, or `nil` when ``timeout`` passed first; the loser is canceled.
    private func download(_ url: URL) async throws -> Data? {
        try await withThrowingTaskGroup(of: Data?.self) { group in
            group.addTask { try await self.fetcher.fetch(url: url) }
            group.addTask {
                try await Task.sleep(for: self.timeout)
                return nil
            }
            defer { group.cancelAll() }
            return try await group.next() ?? nil
        }
    }
}
