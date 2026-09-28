//
//  ViewerError.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Something a request asked for that the viewer cannot give it.
///
/// Every case names the thing by its id, says what happened, and says the request that
/// would work — the same contract the CLI's errors keep, because the endpoints are an
/// API an agent reads. ``status`` is what the connection sends; ``message`` and
/// ``remedy`` are what it puts in the body.
public enum ViewerError: Error, Friendly, CustomStringConvertible {
    /// No watched file has this id.
    case unknownFile(id: String)
    /// The file has no artboard with this id, and here are the ones it does have.
    ///
    /// `available` is never empty: a file with no artboards at all is
    /// ``noArtboards(file:)``, so this message always has ids to offer.
    case unknownArtboard(id: String, file: String, available: [String])
    /// The file has no top-level frames at all, so no artboard can be named.
    ///
    /// Its own case rather than an ``unknownArtboard(id:file:available:)`` with an empty
    /// list, because the two are different answers: one is "not that one, try these",
    /// the other is "there are none yet". The empty list used to reach a message that
    /// quoted the id it was asked for — and on `GET /files/{file}` that id was the empty
    /// string, so the error read `'' cannot be rendered`. A message that can quote
    /// nothing means the branch above it picked the wrong response.
    case noArtboards(file: String)
    /// A `?node=` address named no single node in the file.
    case unknownNode(address: String, file: String, reason: String)
    /// A `?theme=` pin was not `axis:value`.
    case malformedTheme(String)
    /// A numeric query parameter was not a whole number in range.
    case malformedNumber(parameter: String, value: String)
    /// A query parameter naming one of a fixed set of choices named none of them.
    case malformedChoice(parameter: String, value: String, accepted: [String])
    /// An export was asked for in a format nothing writes.
    case unknownFormat(String)
    /// `generate` writes no file of this kind for this artboard.
    case noGeneratedFile(artboard: String, target: String)
    /// The renderer produced no image for an artboard that exists.
    case renderFailed(artboard: String, file: String)
    /// The preview catalog declares no component by this slug.
    ///
    /// `available` is the whole catalog rather than a near-miss list: it is twenty-odd
    /// slugs, the caller is usually looking for one it half-remembers, and a page that
    /// prints the answer costs less than a second request to `/preview`.
    case unknownPreviewComponent(slug: String, available: [String])
    /// The component exists, but declares no state by this slug.
    case unknownPreviewState(component: String, slug: String, available: [String])

    /// What went wrong, naming the thing.
    public var message: String {
        switch self {
        case let .unknownFile(id):
            "No file has id '\(id)'."
        case let .unknownArtboard(id, file, available):
            "File '\(file)' has no artboard '\(id)'. It has: \(available.joined(separator: ", "))."
        case let .noArtboards(file):
            "File '\(file)' has no artboards yet — it holds no top-level frame to render."
        case let .unknownNode(address, file, reason):
            "Node '\(address)' was not found in file '\(file)': \(reason)"
        case let .malformedTheme(pin):
            "Theme pin '\(pin)' is not axis:value."
        case let .malformedNumber(parameter, value):
            "Query parameter '\(parameter)' must be a whole number, not '\(value)'."
        case let .malformedChoice(parameter, value, accepted):
            "Query parameter '\(parameter)' does not take '\(value)'. "
                + "It takes: \(accepted.joined(separator: ", "))."
        case let .unknownFormat(format):
            "Nothing writes '\(format)'. Exportable formats are: "
                + "\(ViewerExportFormat.allCases.map(\.query).joined(separator: ", "))."
        case let .noGeneratedFile(artboard, target):
            "`woodcase generate react` writes no '\(target)' file for artboard '\(artboard)'."
        case let .renderFailed(artboard, file):
            "Artboard '\(artboard)' of '\(file)' could not be rendered."
        case let .unknownPreviewComponent(slug, available):
            "The preview catalog has no component '\(slug)'. It has: "
                + "\(available.joined(separator: ", "))."
        case let .unknownPreviewState(component, slug, available):
            "Component '\(component)' has no preview state '\(slug)'. It has: "
                + "\(available.joined(separator: ", "))."
        }
    }

    /// The request that would work instead.
    public var remedy: String {
        switch self {
        case .unknownFile:
            "GET /files lists the id of every file this server is watching."
        case let .unknownArtboard(_, file, _):
            "GET /files/\(file) lists this file's artboards and their ids."
        case let .noArtboards(file):
            "Add one with `woodcase add <file>.pen frame --name Screen`; "
                + "GET /files/\(file) shows this file as it stands."
        case let .unknownNode(_, file, _):
            "GET /files/\(file)/tree.json without ?node= lists every node's id and name path."
        case .malformedTheme:
            "Pin axes as ?theme=Mode:Dark,Base:Slate — the CLI's Mode=Dark form works too."
        case .malformedNumber:
            "Drop the parameter to use its default, or give it a whole number."
        case let .malformedChoice(parameter, _, accepted):
            "Use ?\(parameter)=\(accepted.first ?? "") — or drop it for the default."
        case .unknownFormat:
            "Ask for one of the formats above; `woodcase render --format` and "
                + "`woodcase generate react` write exactly these."
        case let .noGeneratedFile(artboard, _):
            "A component definition and a top-level frame each generate a .tsx; a "
                + "placed instance ('\(artboard)') generates none. The theme, states "
                + "and manifest files belong to the document, and states.css exists "
                + "only when a component declares interactive states."
        case .renderFailed:
            "Check the file with `woodcase lint`; the artboard may have no settled size."
        case .unknownPreviewComponent:
            "GET \(ViewerLink.previews) is the index: every component, its blurb and its states."
        case let .unknownPreviewState(component, _, _):
            "GET \(ViewerLink.previewComponent(component)) stacks every state this component declares."
        }
    }

    /// The status this failure is served with.
    public var status: HTTPResponse.Status {
        switch self {
        case .unknownFile, .unknownArtboard, .noArtboards, .unknownNode: .notFound
        case .unknownPreviewComponent, .unknownPreviewState: .notFound
        case .malformedTheme, .malformedNumber, .malformedChoice, .unknownFormat: .badRequest
        case .noGeneratedFile: .notFound
        case .renderFailed: .internalServerError
        }
    }

    public var description: String {
        "\(message) \(remedy)"
    }

    /// This failure as the response the client receives.
    ///
    /// - Returns: A JSON body carrying ``message`` and ``remedy``, with ``status``.
    public func response() -> HTTPResponse {
        .failure(status, message: message, remedy: remedy)
    }
}
