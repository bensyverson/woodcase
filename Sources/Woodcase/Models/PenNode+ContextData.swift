//
//  PenNode+ContextData.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    // MARK: Context

    struct ContextData: Friendly {
        public init(
            content: PenValue<String>? = nil
        ) {
            self.content = content
        }

        public var content: PenValue<String>?
    }
}
