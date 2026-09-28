//
//  PenNode+PromptData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Prompt

    struct PromptData: Friendly {
        public init(
            content: PenValue<String>? = nil,
            model: String? = nil
        ) {
            self.content = content
            self.model = model
        }

        public var content: PenValue<String>?
        public var model: String?
    }
}
