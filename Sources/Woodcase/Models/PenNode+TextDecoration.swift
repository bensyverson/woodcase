//
//  PenNode+TextDecoration.swift
//  Woodcase
//

import Foundation

public extension PenNode {
    /// The underline and strikethrough this text node's metadata protects from Pen
    /// (``PenMetadata/WoodcaseKey/textDecoration``), stale or not; `nil` for a node that is
    /// not a `text`, holds none, or holds one that cannot be read.
    var textDecoration: PenTextDecoration? {
        guard case .text = kind, let value = common.metadata?[woodcase: .textDecoration] else { return nil }
        return try? PenTextDecoration(metadataValue: value)
    }

    /// This node with its native underline and strikethrough and their protection in step,
    /// or the node itself when it is not a `text` or has nothing to change.
    ///
    /// For a text whose content is a literal:
    ///
    /// 1. **Restore.** A native key the node does not write is restored from protection
    ///    made for its content — the key Pen stripped when it opened the file. A key the
    ///    node does write wins, whatever the protection says.
    /// 2. **Protect.** The protection is then rewritten from the native keys: made for the
    ///    content and holding each one that is literally `true`, or removed when neither
    ///    is. A stale protection — made for words Pen has since edited — so goes.
    ///
    /// A text whose content is a variable is left alone: there is no literal to make the
    /// protection for, and so nothing to tell a stale one by.
    ///
    /// - Returns: The node, protected.
    func protectingTextDecoration() -> PenNode {
        guard case var .text(data) = kind, let content = data.content?.literalValue else { return self }
        let fresh = textDecoration.flatMap { $0.isStale(for: content) ? nil : $0 }
        if data.underline == nil, fresh?.underline == true { data.underline = .literal(true) }
        if data.strikethrough == nil, fresh?.strikethrough == true { data.strikethrough = .literal(true) }

        let underline = data.underline?.literalValue == true
        let strikethrough = data.strikethrough?.literalValue == true
        let protection = underline || strikethrough
            ? PenTextDecoration(text: content, underline: underline, strikethrough: strikethrough)
            : nil
        var node = self
        node.kind = .text(data)
        let wanted = protection?.metadataValue
        if common.metadata?[woodcase: .textDecoration] != wanted {
            var metadata = common.metadata ?? PenMetadata(type: nil)
            metadata[woodcase: .textDecoration] = wanted
            node.common.metadata = metadata.typedForWriting()
        }
        return node
    }

    /// Whether ``protectingTextDecoration()`` could change the node: a text that carries
    /// a native `underline` or `strikethrough`, or holds a protection.
    internal var mayNeedTextDecorationProtection: Bool {
        guard case let .text(data) = kind else { return false }
        return data.underline != nil || data.strikethrough != nil || common.metadata?[woodcase: .textDecoration] != nil
    }
}

public extension PenDocument {
    /// The document with every text node's underline and strikethrough protected from Pen
    /// (``PenNode/protectingTextDecoration()``), in `children` at any depth.
    ///
    /// ``PenParser`` applies it to every document it reads and writes, so a file Pen saved
    /// reads with the keys it stripped and is written with them restored.
    ///
    /// - Returns: The document, protected; `self` where no text changed.
    func protectingTextDecoration() -> PenDocument {
        // Most documents have nothing to protect; find out without rebuilding the tree.
        var pending = children
        var anyToProtect = false
        while let node = pending.popLast(), !anyToProtect {
            anyToProtect = node.mayNeedTextDecorationProtection
            pending += node.kind.inlineChildren
        }
        guard anyToProtect else { return self }
        var document = self
        document.children = PenTreeRewrite.rewrite(children, context: ()) { node, _ in
            .descend(node.protectingTextDecoration(), ())
        }
        return document
    }
}
