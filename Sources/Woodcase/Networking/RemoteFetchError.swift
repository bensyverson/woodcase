//
//  RemoteFetchError.swift
//  Woodcase
//

import Foundation

/// Errors raised by a ``RemoteDataFetching`` implementation.
///
/// Transport-level only: what the *caller* makes of a failed fetch is its own business.
/// The two cases are the distinction a caller needs: the server *answered* (and said no),
/// or the request never got an answer at all. ``GoogleFontResolver`` turns a 404 into
/// ``GoogleFontError/familyNotFound(_:)`` and everything else into
/// ``GoogleFontError/networkUnavailable(family:failure:)``, so a blocked network no longer
/// reads as a font that does not exist.
public enum RemoteFetchError: Error, Friendly {
    /// The server answered with a status other than 200.
    case httpError(statusCode: Int)

    /// The request never got an answer: no DNS, no route, a refused proxy, a certificate
    /// that could not be checked. The ``NetworkFailure`` says which.
    case unreachable(NetworkFailure)
}
