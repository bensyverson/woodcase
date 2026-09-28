//
//  LocalGoogleFontsFetcher.swift
//  WoodcaseTests
//

import Foundation
import os
@testable import Woodcase

/// A stand-in for raw.githubusercontent.com's google/fonts tree, served from one local
/// directory, that remembers every file it was asked for.
///
/// A request for `…/<license>/<dir>/METADATA.pb` reads `<dir>.METADATA.pb`, and any other
/// file reads its own name, so one flat directory serves several families. Anything not
/// there answers 404, as GitHub would — so a family's METADATA is found under whichever
/// license directory the resolver probes first.
///
/// ``committed`` serves `Tests/WoodcaseTests/Fonts/GoogleFonts`: copies of
/// `google/fonts` `main` (`ofl/{ibmplexmono,spectral,lora,inter,instrumentserif}`, fetched
/// 2026-09-27), each family's METADATA.pb and OFL.txt beside the files
/// `render-font-faces.pen` draws. The fonts are OFL-licensed, so they may travel.
final class LocalGoogleFontsFetcher: RemoteDataFetching, Sendable {
    /// The directory the files are served from.
    let directory: URL

    private let requests = OSAllocatedUnfairLock<[String]>(initialState: [])

    /// The committed Google Fonts files.
    static let committedDirectory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .appendingPathComponent("Fonts")
        .appendingPathComponent("GoogleFonts")

    /// A fetcher serving the committed Google Fonts files.
    static var committed: LocalGoogleFontsFetcher {
        LocalGoogleFontsFetcher(directory: committedDirectory)
    }

    /// A fetcher serving `directory`.
    init(directory: URL) {
        self.directory = directory
    }

    /// Every file name requested so far, as `<dir>/<file>`, in order, 404s included.
    var requested: [String] {
        requests.withLock { $0 }
    }

    /// The font files requested so far (METADATA.pb left out), as `<dir>/<file>`.
    var requestedFontFiles: [String] {
        requested.filter { !$0.hasSuffix("/METADATA.pb") }
    }

    func fetch(url: URL) async throws -> Data {
        let components = url.pathComponents
        let file = components.last ?? ""
        let family = components.count >= 2 ? components[components.count - 2] : ""
        requests.withLock { $0.append("\(family)/\(file)") }
        let local = file == "METADATA.pb" ? "\(family).METADATA.pb" : file
        guard let data = FileManager.default.contents(atPath: directory.appendingPathComponent(local).path) else {
            throw RemoteFetchError.httpError(statusCode: 404)
        }
        return data
    }
}
