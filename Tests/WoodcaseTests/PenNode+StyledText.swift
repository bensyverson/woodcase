//
//  PenNode+StyledText.swift
//  WoodcaseTests
//

import Foundation
import Woodcase

extension PenNode {
    /// A text node holding `spans` in its `metadata.woodcase.spans`, as a file stores them.
    ///
    /// - Parameters:
    ///   - data: The text's data.
    ///   - spans: Its rich text, or `nil` for none.
    ///   - id: The node's id.
    /// - Returns: The node.
    static func text(_ data: PenNode.TextData, spans: PenTextSpans?, id: String = "t") -> PenNode {
        var metadata: PenMetadata?
        if let spans {
            var written = PenMetadata(type: nil)
            written.textSpans = spans
            metadata = written
        }
        return PenNode(id: id, common: PenNodeCommon(metadata: metadata), kind: .text(data))
    }
}
