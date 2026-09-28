//
//  OfflineRenderCache.swift
//  WoodcaseViewerTests
//

import Foundation
import Woodcase
@testable import WoodcaseViewer

/// A ``RemoteDataFetching`` that never opens a socket.
///
/// The viewer's fixtures name faces this machine may not have — "Inter" in eighty-eight
/// nodes — and a `RenderCache` over the shared resolvers answers that by downloading
/// them from GitHub into the user's `$WOODCASE_HOME`. In a test that is three bugs: the
/// suite fails offline, it writes a directory the user owns, and the download is an
/// `await` on `URLSession`'s seven-day resource timeout rather than on any deadline of
/// ours. Every fetch here fails immediately instead, which is exactly what the resolvers
/// are built to survive: an unresolved family falls back to SF Pro and an unresolved
/// image fill is not drawn.
///
/// It is deliberately *not* a fixture server. A viewer test that needs a real face
/// should name one the repo ships (`Tests/WoodcaseTests/Fonts` holds IBM Plex Sans and
/// JetBrains Mono) and register it from that file, so the face comes from the repository
/// rather than from a mock's idea of what GitHub would have answered.
struct OfflineFetcher: RemoteDataFetching {
    /// Fails without touching the network.
    ///
    /// - Parameter url: The URL a resolver would have fetched.
    /// - Returns: Never; this always throws.
    /// - Throws: ``RemoteFetchError/httpError(statusCode:)`` with 599, the
    ///   conventional "no response" code, so a resolver takes its unresolved path.
    func fetch(url _: URL) async throws -> Data {
        throw RemoteFetchError.httpError(statusCode: 599)
    }
}

extension ViewerFixtures {
    /// The one directory the offline caches are rooted at.
    ///
    /// Never created: every fetch fails, so nothing is ever written here. It exists so
    /// the resolvers cannot read the *user's* cache either — a machine with Inter in
    /// `~/.woodcase/fonts` would otherwise render these fixtures in a face a clean
    /// checkout does not have, and the suite would pass for a reason it cannot repeat.
    static let offlineCacheRoot = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("woodcase-viewer-tests-offline-cache", isDirectory: true)

    /// The font resolver every viewer test renders through.
    ///
    /// One instance for the target rather than one per test, matching production's
    /// single ``GoogleFontResolver/shared``: registration is process-global anyway, and
    /// a shared resolver says "font 'Inter' could not be resolved" once instead of once
    /// per `RenderCache`.
    static let offlineFonts = GoogleFontResolver(
        cache: GoogleFontCache(rootDirectory: offlineCacheRoot.appendingPathComponent("fonts")),
        fetcher: OfflineFetcher()
    )

    /// The remote-image resolver every viewer test renders through, on the same terms.
    static let offlineImages = RemoteImageResolver(
        cache: RemoteImageCache(rootDirectory: offlineCacheRoot.appendingPathComponent("images")),
        fetcher: OfflineFetcher()
    )

    /// A ``RenderCache`` that cannot reach the network.
    ///
    /// The only `RenderCache` a viewer test builds. `HermeticNetworkTests` enforces
    /// that by scanning the sources: `RenderCache()` takes the shared, network-backed
    /// resolvers by default, and a default argument is invisible at the call site.
    ///
    /// - Returns: A fresh, empty cache over the target's offline resolvers.
    static func renders() -> RenderCache {
        RenderCache(fonts: offlineFonts, images: offlineImages)
    }
}
