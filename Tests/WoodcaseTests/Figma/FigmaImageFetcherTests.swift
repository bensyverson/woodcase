//
//  FigmaImageFetcherTests.swift
//  WoodcaseTests
//

import CryptoKit
import Foundation
import Testing
@testable import Woodcase

/// `FigmaImageFetcher` downloads the images a Figma clipboard names by hash, through an
/// injected ``RemoteDataFetching``, so none of these touch the network.
struct FigmaImageFetcherTests {
    /// Answers each URL from a table; an absent URL is a 404. Counts how many fetches run
    /// at once, and can hold each for a while.
    actor TableFetcher: RemoteDataFetching {
        let table: [URL: Data]
        let delay: Duration
        private(set) var inFlight = 0
        private(set) var peak = 0

        init(_ table: [String: Data], delay: Duration = .zero) {
            self.table = Dictionary(uniqueKeysWithValues: table.map { (URL(string: $0.key)!, $0.value) })
            self.delay = delay
        }

        func fetch(url: URL) async throws -> Data {
            inFlight += 1
            peak = max(peak, inFlight)
            defer { inFlight -= 1 }
            if delay > .zero { try await Task.sleep(for: delay) }
            guard let data = table[url] else { throw RemoteFetchError.httpError(statusCode: 404) }
            return data
        }
    }

    /// A PNG signature and some bytes after it.
    static let png = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 1, 2, 3])

    /// The SHA-1 of `data` as lowercase hex: a Figma image hash.
    static func hash(_ data: Data) -> String {
        Insecure.SHA1.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    @Test("Each hash's bytes come back with their format")
    func fetches() async throws {
        let hash = Self.hash(Self.png)
        let fetcher = FigmaImageFetcher(fetcher: TableFetcher(["https://example.test/a": Self.png]))
        let results = await fetcher.fetch([hash: "https://example.test/a"])
        let image = try results[hash]?.get()
        #expect(image == FigmaImageFetcher.FetchedImage(data: Self.png, format: .png))
        #expect(results.count == 1)
    }

    @Test("A server that says no is a failed fetch carrying its status")
    func httpError() async {
        let fetcher = FigmaImageFetcher(fetcher: TableFetcher([:]))
        let results = await fetcher.fetch(["ab": "https://example.test/missing"])
        #expect(results["ab"] == .failure(.fetchFailed(.httpError(statusCode: 404))))
    }

    @Test("Bytes whose SHA-1 is not the hash are refused")
    func hashMismatch() async {
        let wrong = String(repeating: "0", count: 40)
        let fetcher = FigmaImageFetcher(fetcher: TableFetcher(["https://example.test/a": Self.png]))
        let results = await fetcher.fetch([wrong: "https://example.test/a"])
        #expect(results[wrong] == .failure(.hashMismatch(actual: Self.hash(Self.png))))
    }

    @Test("Bytes that are not PNG, JPEG, GIF or WebP are refused")
    func unrecognized() async {
        let text = Data("<html>".utf8)
        let hash = Self.hash(text)
        let fetcher = FigmaImageFetcher(fetcher: TableFetcher(["https://example.test/a": text]))
        let results = await fetcher.fetch([hash: "https://example.test/a"])
        #expect(results[hash] == .failure(.unrecognizedFormat))
    }

    @Test("A URL that is not https is refused without a fetch", arguments: ["", "file:///etc/hosts", "http://example.test/a"])
    func invalidURL(url: String) async {
        let table = TableFetcher(["file:///etc/hosts": Self.png, "http://example.test/a": Self.png])
        let results = await FigmaImageFetcher(fetcher: table).fetch(["ab": url])
        #expect(results["ab"] == .failure(.invalidURL(url)))
        #expect(await table.peak == 0)
    }

    @Test("A fetch that outlasts the timeout fails as timed out, promptly")
    func timeout() async {
        let slow = TableFetcher(["https://example.test/a": Self.png], delay: .seconds(30))
        let fetcher = FigmaImageFetcher(fetcher: slow, timeout: .milliseconds(50))
        let start = ContinuousClock.now
        let results = await fetcher.fetch(["ab": "https://example.test/a"])
        #expect(results["ab"] == .failure(.timedOut))
        #expect(ContinuousClock.now - start < .seconds(10))
    }

    @Test("No more fetches run at once than the bound")
    func boundedConcurrency() async {
        var table: [String: Data] = [:]
        var hashes: [String: String] = [:]
        for index in 0 ..< 10 {
            let data = Self.png + Data([UInt8(index)])
            table["https://example.test/\(index)"] = data
            hashes[Self.hash(data)] = "https://example.test/\(index)"
        }
        let network = TableFetcher(table, delay: .milliseconds(20))
        let results = await FigmaImageFetcher(fetcher: network, maximumConcurrentFetches: 3).fetch(hashes)
        #expect(results.count == 10)
        #expect(results.values.allSatisfy { (try? $0.get()) != nil })
        #expect(await network.peak == 3)
    }

    @Test("One image can be fetched on its own")
    func single() async {
        let hash = Self.hash(Self.png)
        let fetcher = FigmaImageFetcher(fetcher: TableFetcher(["https://example.test/a": Self.png]))
        let result = await fetcher.fetch(hash: hash, url: "https://example.test/a")
        #expect(result == .success(FigmaImageFetcher.FetchedImage(data: Self.png, format: .png)))
    }

    @Test("The bound holds across separate calls on one fetcher")
    func boundedAcrossCalls() async {
        var table: [String: Data] = [:]
        var hashes: [(String, String)] = []
        for index in 0 ..< 8 {
            let data = Self.png + Data([UInt8(index)])
            table["https://example.test/\(index)"] = data
            hashes.append((Self.hash(data), "https://example.test/\(index)"))
        }
        let network = TableFetcher(table, delay: .milliseconds(20))
        let fetcher = FigmaImageFetcher(fetcher: network, maximumConcurrentFetches: 2)
        let successes = await withTaskGroup(of: Bool.self) { group in
            for (hash, url) in hashes {
                group.addTask { await (try? fetcher.fetch(hash: hash, url: url).get()) != nil }
            }
            return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
        }
        #expect(successes == 8)
        #expect(await network.peak == 2)
    }

    @Test("A fetch canceled while it waits for a slot fails as canceled, without fetching")
    func canceledWhileWaiting() async {
        let slow = TableFetcher(["https://example.test/a": Self.png], delay: .seconds(30))
        let fetcher = FigmaImageFetcher(fetcher: slow, maximumConcurrentFetches: 1)
        let holder = Task { await fetcher.fetch(hash: "aa", url: "https://example.test/a") }
        let deadline = ContinuousClock.now + .seconds(10)
        while await slow.peak == 0, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(5))
        }
        let waiter = Task { await fetcher.fetch(hash: "bb", url: "https://example.test/a") }
        waiter.cancel()
        #expect(await waiter.value == .failure(.cancelled))
        holder.cancel()
        #expect(await holder.value == .failure(.cancelled))
        #expect(await slow.peak == 1)
    }
}
