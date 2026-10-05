//
//  DocumentLinter+ComponentLoops.swift
//  Woodcase
//

import Foundation

/// The ``LintCheck/componentLoop`` check: components that contain each other.
extension DocumentLinter {
    /// One finding per component loop the document holds, at the loop's first member.
    ///
    /// - Parameter document: The document.
    /// - Returns: The findings, in the order ``EditableDocument/componentLoops`` gives.
    static func componentLoopFindings(in document: EditableDocument) -> [LintFinding] {
        document.componentLoops.map { loop in
            let first = loop.members[0].id
            return LintFinding(
                check: .componentLoop,
                nodeID: first,
                path: document.nodes[first] != nil ? document.namePath(of: first) : nil,
                message: "renders an instance of itself: \(loop). Components that contain each other are "
                    + "a design error, and that nesting is not drawn; remove the instance that closes the loop."
            )
        }
    }
}
