//
//  GoogleFontResolver+Metadata.swift
//  Woodcase
//

import Foundation

/// Fetching and parsing METADATA.pb from the google/fonts GitHub repository.
extension GoogleFontResolver {
    /// The status that means "this license directory has no such family".
    private static let notFoundStatus = 404

    /// Fetches and parses METADATA.pb for a font family from GitHub.
    ///
    /// Probes `ofl/`, `apache/`, and `ufl/` directories in order.
    ///
    /// - Parameter family: The font family name.
    /// - Returns: The parsed metadata.
    /// - Throws: ``GoogleFontError/familyNotFound(_:)`` if every directory answers 404,
    ///   ``GoogleFontError/networkUnavailable(family:failure:)`` if any fetch fails
    ///   otherwise.
    func fetchMetadata(family: String) async throws -> GoogleFontMetadata {
        let (metadata, _) = try await fetchMetadataWithLicense(family: family)
        return metadata
    }

    /// Fetches METADATA.pb and returns both the parsed metadata and the license directory.
    func fetchMetadataWithLicense(
        family: String
    ) async throws -> (GoogleFontMetadata, String) {
        let (metadata, license, _) = try await fetchMetadataData(family: family)
        return (metadata, license)
    }

    /// Fetches METADATA.pb: the parsed metadata, the license directory it was found
    /// under, and its bytes as fetched, for the cache.
    func fetchMetadataData(
        family: String
    ) async throws -> (GoogleFontMetadata, String, Data) {
        let dirName = GoogleFontCache.directoryName(for: family)

        for license in Self.licenseDirectories {
            let urlString = "\(Self.githubBaseURL)/\(license)/\(dirName)/METADATA.pb"
            guard let url = URL(string: urlString) else { continue }
            let data: Data
            do {
                data = try await fetcher.fetch(url: url)
            } catch RemoteFetchError.httpError(statusCode: Self.notFoundStatus) {
                continue
            } catch {
                // Anything but a 404 means the repository never said "no": probing the
                // next directory would fail the same way, and "not found" would be a lie.
                throw GoogleFontError.networkUnavailable(family: family, failure: Self.fetchFailure(error))
            }
            guard let metadata = try? GoogleFontMetadata.parse(data) else { continue }
            return (metadata, license, data)
        }

        throw GoogleFontError.familyNotFound(family)
    }

    /// A fetch error as the typed transport error it should be.
    ///
    /// ``URLSessionDataFetcher`` only ever throws ``RemoteFetchError``; a custom fetcher
    /// may throw anything, and that is still a fetch that got no answer.
    static func fetchFailure(_ error: Error) -> RemoteFetchError {
        error as? RemoteFetchError
            ?? .unreachable(NetworkFailure(classifying: error, trustEvaluationCode: nil, proxy: nil))
    }
}
