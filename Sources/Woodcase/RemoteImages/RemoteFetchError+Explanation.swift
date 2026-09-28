//
//  RemoteFetchError+Explanation.swift
//  Woodcase
//

import Foundation

/// The one clause a download-failure warning needs: what went wrong, in a form that
/// reads in the middle of a sentence.
///
/// Shared between ``RemoteImageResolver`` and ``GoogleFontResolver``, which both
/// download over `http(s)` through a ``RemoteDataFetching`` and both owe their reader
/// the same two facts: the server answered and said no (``RemoteFetchError/httpError(statusCode:)``),
/// or the request never got an answer at all (``RemoteFetchError/unreachable(_:)``, whose
/// ``NetworkFailure`` says which). Living beside a resolver rather than in
/// `Sources/Woodcase/Networking/` keeps the wording — "the server answered HTTP 404" — a
/// decision the two callers make together, not one `RemoteFetchError` itself has an
/// opinion about.
extension RemoteFetchError {
    /// What went wrong, without a leading "because" or a trailing period.
    var reasonPhrase: String {
        switch self {
        case let .unreachable(networkFailure): networkFailure.description
        case let .httpError(statusCode): "the server answered HTTP \(statusCode)"
        }
    }
}
