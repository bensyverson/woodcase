//
//  EmitContext+Warnings.swift
//  Woodcase
//

extension EmitContext {
    /// One generate-time warning about one node.
    struct IssuedWarning: Friendly {
        /// The warning's text.
        var message: String
        /// The node it names.
        var nodeID: String
    }

    /// Warns `message` about the node `nodeID`, once per file: a node emitted twice in one
    /// file — a variant, an inlined instance — is named once.
    func warnOnce(_ message: String, nodeID: String) {
        guard issuedWarnings.insert(IssuedWarning(message: message, nodeID: nodeID)).inserted else { return }
        diagnostics?.warn(message, stage: .codeGen, nodeID: nodeID)
    }
}
