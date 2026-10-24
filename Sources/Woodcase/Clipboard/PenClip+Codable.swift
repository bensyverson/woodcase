//
//  PenClip+Codable.swift
//  Woodcase
//

import Foundation

public extension PenClip {
    /// The keys a clip's JSON writes.
    enum CodingKeys: String, CodingKey {
        case document, contentIDs, origins, sourceDocumentID, connectorIDs
    }

    /// Decodes a clip; one that does not say which connectors it carried
    /// (``connectorIDs``) — written by hand, or before connectors were carried —
    /// carries none.
    ///
    /// - Parameter decoder: The decoder.
    /// - Throws: A decoding error for a clip without its document or content ids.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            document: container.decode(PenDocument.self, forKey: .document),
            contentIDs: container.decode([String].self, forKey: .contentIDs),
            origins: container.decodeIfPresent([String: Origin].self, forKey: .origins),
            sourceDocumentID: container.decodeIfPresent(String.self, forKey: .sourceDocumentID),
            connectorIDs: container.decodeIfPresent([String].self, forKey: .connectorIDs) ?? []
        )
    }
}
