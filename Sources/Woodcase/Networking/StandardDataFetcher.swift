//
//  StandardDataFetcher.swift
//  Woodcase
//

import Foundation

/// The production ``RemoteDataFetching`` for this platform — the one construction point
/// the shared resolvers use.
///
/// Everywhere it starts with ``URLSessionDataFetcher``, which honors the proxy
/// environment. On macOS that is wrapped in a ``TrustFallbackDataFetcher`` with a
/// ``CurlDataFetcher`` behind it, so a process that cannot reach the system
/// certificate-trust service (the Claude Code Bash sandbox) still downloads, through
/// `/usr/bin/curl`. Linux needs no fallback — FoundationNetworking is libcurl and reads
/// the proxy variables itself — and iOS has no `Process` to run curl with.
public enum StandardDataFetcher {
    /// Builds the fetcher for this platform, routed by `environment`'s proxy variables.
    ///
    /// - Parameter environment: The variables to read, `ProcessInfo`'s by default. On
    ///   macOS the curl fallback is launched with exactly this environment.
    /// - Returns: The composed fetcher.
    public static func make(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> any RemoteDataFetching {
        let urlSession = URLSessionDataFetcher(environment: environment)
        #if os(macOS)
            return TrustFallbackDataFetcher(primary: urlSession, fallback: CurlDataFetcher(environment: environment))
        #else
            return urlSession
        #endif
    }
}
