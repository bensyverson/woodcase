//
//  FigmaGUID.swift
//  Woodcase
//

/// A Figma node's GUID: the session that made it and its number in that session.
struct FigmaGUID: Friendly {
    /// The session that created the node.
    var sessionID: UInt32
    /// The node's number within its session.
    var localID: UInt32

    /// A GUID of `sessionID` and `localID`.
    init(sessionID: UInt32, localID: UInt32) {
        self.sessionID = sessionID
        self.localID = localID
    }

    /// Reads a `GUID` struct, or `nil` when `value` is not one.
    init?(_ value: KiwiValue?) {
        guard let session = value?["sessionID"]?.uintValue, let local = value?["localID"]?.uintValue else { return nil }
        self.init(sessionID: session, localID: local)
    }

    /// The id of the Pen node made from this Figma node.
    var penID: String {
        FigmaImporter.penID(sessionID: sessionID, localID: localID)
    }
}
