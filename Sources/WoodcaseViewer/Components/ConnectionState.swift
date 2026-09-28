//
//  ConnectionState.swift
//  WoodcaseViewer
//

import Foundation
import Woodcase

/// Whether the page is still hearing from the server.
///
/// Three states, one word each, and the word is the point: the badge went amber when the
/// stream died but went on reading "live", which is the one thing a connection indicator
/// must never do. Naming the *fact* as a type keeps the three labels, the three
/// stylesheet rules and the two strings ``ViewerScript`` writes from drifting apart —
/// the script interpolates ``rawValue`` and the server renders ``label``, so there is
/// one source for both.
public enum ConnectionState: String, Friendly, CaseIterable {
    /// The page has loaded and the `EventSource` has not opened yet.
    case connecting

    /// The stream is open: everything on screen is as fresh as the file.
    case live

    /// The stream errored — the server went away, or the network did.
    case lost

    /// What the badge reads in this state.
    ///
    /// `lost` reads *disconnected* rather than *lost*: the raw value names the event the
    /// script saw, and the label names what it means to the person reading it. And
    /// `connecting` carries an ellipsis, which the raw value cannot: it is the one state
    /// still in progress, and the word says so.
    public var label: String {
        switch self {
        case .connecting: "connecting…"
        case .live: "live"
        case .lost: "disconnected"
        }
    }
}
