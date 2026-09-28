//
//  HermeticNetworkTests.swift
//  Woodcase
//

import Foundation
import Testing

/// Proves, by reading the suite's own source, that no test can reach the network.
///
/// The library has exactly one networking seam — ``RemoteDataFetching`` — and the
/// production composition of it, `StandardDataFetcher`, opens sockets: `URLSession`
/// first and, on macOS, `/usr/bin/curl` behind it. The two
/// process-wide resolvers built over it, `GoogleFontResolver.shared` and
/// `RemoteImageResolver.shared`, are production objects: they download from GitHub and
/// write the user's `$WOODCASE_HOME`. A suite that touches either is not hermetic — it
/// fails behind a captive portal, it mutates a directory the user owns, and a stalled
/// fetch is an `await` on `URLSession`'s seven-day resource timeout rather than on a
/// deadline of ours.
///
/// A runtime assertion cannot catch this: the leak is a *default argument*, so the call
/// that reaches the network reads as `RenderCache()` and is invisible at every level
/// above it. So this reads the sources instead. It is a lint, not a unit test, and it
/// is deliberately blunt: adding a network-backed object to a test means adding an
/// allowlist entry with a sentence saying why, which is the review this is for.
@Suite("Hermetic tests")
struct HermeticNetworkTests {
    /// The `Tests` directory, from this file's own path.
    static let testsDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    /// A file allowed to name a network-backed type, and why.
    struct Exemption {
        /// The file's name, without its directory.
        let file: String
        /// Why this file is allowed to name it — read on every change to this list.
        let reason: String
    }

    /// The files allowed to name a production fetcher or a shared resolver.
    ///
    /// One entry per file, each with the sentence that earns it. Nothing is exempt for
    /// being inconvenient to change: a test that would genuinely fetch belongs behind a
    /// mock fetcher, not on this list.
    static let exemptions: [Exemption] = [
        Exemption(
            file: "HermeticNetworkTests.swift",
            reason: """
            This file is the scan itself: it has to spell the names it forbids.
            """
        ),
        Exemption(
            file: "PenRemoteImageProviderTests.swift",
            reason: """
            The fetcher there is inert. The test seeds the image cache directly and \
            exercises PenRenderer.imageProvider, whose remote half is the synchronous \
            RemoteImageResolver.cachedImage(for:) — a disk read. No fetch is ever \
            issued, so this is the one place the real fetcher stands in as filler for \
            an initialiser argument that is never used.
            """
        ),
        Exemption(
            file: "StandardDataFetcherTests.swift",
            reason: """
            It inspects what StandardDataFetcher.make composes — which fetcher is \
            primary and which is the fallback — and never calls fetch on it.
            """
        ),
    ]

    /// The names a test may not write, and what to do instead.
    static let forbidden: [(needle: String, remedy: String)] = [
        (
            "URLSessionDataFetcher",
            "inject a RemoteDataFetching that answers from fixtures, as GoogleFontResolverTests does"
        ),
        (
            "StandardDataFetcher",
            "inject a RemoteDataFetching that answers from fixtures, as GoogleFontResolverTests does"
        ),
        (
            "GoogleFontResolver.shared",
            "build a GoogleFontResolver over a temporary GoogleFontCache and a mock fetcher"
        ),
        (
            "RemoteImageResolver.shared",
            "build a RemoteImageResolver over a temporary RemoteImageCache and a mock fetcher"
        ),
    ]

    /// Every Swift file under `Tests`, with its code — comment lines removed.
    ///
    /// Whole-line comments go because a doc comment that *names* the forbidden shape in
    /// order to warn about it is not an offence, and the file that explains the rule is
    /// exactly the file most likely to spell it. Only lines whose first non-space
    /// characters are `//` are dropped; a trailing comment is left alone, since
    /// stripping to end-of-line would also cut a `https://` inside a string literal and
    /// hide whatever followed it.
    static func sources() throws -> [(name: String, path: String, code: String)] {
        let enumerator = try #require(FileManager.default.enumerator(
            at: testsDirectory, includingPropertiesForKeys: nil
        ))
        var files: [(String, String, String)] = []
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            let text = try String(contentsOf: url, encoding: .utf8)
            let code = text
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
                .joined(separator: "\n")
            files.append((
                url.lastPathComponent,
                url.path.replacingOccurrences(of: testsDirectory.path + "/", with: ""),
                code
            ))
        }
        return files
    }

    @Test("No test names a network-backed fetcher or resolver outside the allowlist")
    func noTestReachesTheNetwork() throws {
        let allowed = Set(Self.exemptions.map(\.file))
        var offences: [String] = []
        for source in try Self.sources() where !allowed.contains(source.name) {
            for rule in Self.forbidden where source.code.contains(rule.needle) {
                offences.append("\(source.path) names \(rule.needle) — \(rule.remedy)")
            }
        }
        #expect(offences.isEmpty, "\(offences.joined(separator: "\n"))")
    }

    @Test("Every RenderCache a test builds names the resolvers it renders through")
    func everyRenderCacheNamesItsResolvers() throws {
        // RenderCache's resolver parameters default to the shared, network-backed pair,
        // so a bare `RenderCache()` in a test is the leak this suite is about — and it
        // reads like nothing at all. Naming them is the whole guard.
        let construction = /RenderCache\((?<arguments>[^)]*)\)/
        var offences: [String] = []
        for source in try Self.sources() where source.name != "HermeticNetworkTests.swift" {
            for match in source.code.matches(of: construction)
                where !match.arguments.contains("fonts:")
            {
                offences.append(
                    "\(source.path) builds RenderCache(\(match.arguments)) without `fonts:`; "
                        + "use ViewerFixtures.renders() or pass offline resolvers"
                )
            }
        }
        #expect(offences.isEmpty, "\(offences.joined(separator: "\n"))")
    }

    @Test("No library code settles through the shared font resolver unless a caller names it")
    func noLibraryDefaultReachesTheSharedFontResolver() throws {
        // A settled read — tree, lint, a write's lint preview, a script's doc.tree() —
        // registers fonts through the resolver on the document's read context. If any
        // library code defaulted that resolver to the shared one, every test that
        // settles a document would measure in whatever faces the reader's
        // $WOODCASE_HOME happens to hold, and pass for a reason a clean checkout cannot
        // repeat. With no such default, a test reaches the shared resolver only by
        // naming it, which the scan above forbids. The declaration itself is the one
        // line allowed to spell it.
        let sources = Self.testsDirectory.deletingLastPathComponent().appendingPathComponent("Sources")
        let libraries = ["Woodcase", "WoodcaseScripting"]
        let offence = /GoogleFontResolver\??\s*=\s*\.shared|GoogleFontResolver\.shared|fontResolver:\s*\.shared|fonts:\s*\.shared/
        var offences: [String] = []
        for library in libraries {
            let enumerator = try #require(FileManager.default.enumerator(
                at: sources.appendingPathComponent(library), includingPropertiesForKeys: nil
            ))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                let lines = try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
                for line in lines where !line.trimmingCharacters(in: .whitespaces).hasPrefix("//") {
                    guard line.contains(offence), !line.contains("static let shared = GoogleFontResolver(") else {
                        continue
                    }
                    offences.append("\(library)/\(url.lastPathComponent): \(line.trimmingCharacters(in: .whitespaces))")
                }
            }
        }
        #expect(offences.isEmpty, "name the resolver at the call site instead:\n\(offences.joined(separator: "\n"))")
    }

    @Test("Every allowlist entry names a file that exists and says why")
    func allowlistIsCurrent() throws {
        let names = try Set(Self.sources().map(\.name))
        // Compared as names rather than with `#expect(names.contains(…))`, which would
        // print all four hundred test files into the failure.
        let stale = Self.exemptions.map(\.file).filter { !names.contains($0) }
        #expect(stale.isEmpty, "allowlist names files that no longer exist: \(stale)")
        let unexplained = Self.exemptions.filter { $0.reason.count < 40 }.map(\.file)
        #expect(unexplained.isEmpty, "allowlist entries with no real reason: \(unexplained)")
    }
}
