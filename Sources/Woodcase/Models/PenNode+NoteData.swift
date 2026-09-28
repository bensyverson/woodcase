//
//  PenNode+NoteData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Note

    struct NoteData: Friendly {
        public init(content: PenValue<String>? = nil) {
            self.content = content
        }

        public var content: PenValue<String>?
    }
}
