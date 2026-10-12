//
//  PenLayoutEngine+Properties.swift
//  Woodcase
//

import Foundation

// MARK: - Declared Sizing

extension PenLayoutEngine {
    /// The sizing this engine lays a node's width out by, defaults included.
    ///
    /// Not the same thing as the node's declared `width`: an absent width is
    /// `fit_content`, and a `group` has no width of its own at all — it is always
    /// `fit_content` around its children. Anything reasoning about sizing (``DocumentLinter``
    /// does) asks here rather than reading the property, so there is one answer to
    /// "what does `fill_container` mean on this node" and the layout owns it.
    ///
    /// - Parameter node: The node to ask about.
    /// - Returns: The width sizing the layout pass uses.
    static func widthSizing(of node: PenNode) -> PenSizing {
        extractLayoutProperties(node).widthSizing
    }

    /// The sizing this engine lays a node's height out by, defaults included.
    ///
    /// - Parameter node: The node to ask about.
    /// - Returns: The height sizing the layout pass uses.
    /// - SeeAlso: ``widthSizing(of:)``
    static func heightSizing(of node: PenNode) -> PenSizing {
        extractLayoutProperties(node).heightSizing
    }
}

// MARK: - Property Extraction

extension PenLayoutEngine {
    static func extractLayoutProperties(_ node: PenNode) -> NodeLayoutProperties {
        switch node.kind {
        case let .frame(data):
            NodeLayoutProperties(
                widthSizing: data.width ?? .fitContent(fallback: nil),
                heightSizing: data.height ?? .fitContent(fallback: nil),
                layout: data.layout ?? .horizontal,
                gap: data.gap?.literalValue ?? 0,
                padding: data.padding?.resolve() ?? .zero,
                justifyContent: data.justifyContent ?? .start,
                alignItems: data.alignItems ?? .start,
                children: data.children ?? [],
                isContainer: true,
                textInput: nil
            )
        case let .group(data):
            // A group has no layout properties of its own: it is always an
            // absolute container whose children sit at their own explicit x/y.
            NodeLayoutProperties(
                widthSizing: .fitContent(fallback: nil),
                heightSizing: .fitContent(fallback: nil),
                layout: .none,
                gap: 0,
                padding: .zero,
                justifyContent: .start,
                alignItems: .start,
                children: data.children ?? [],
                isContainer: true,
                textInput: nil
            )
        default:
            NodeLayoutProperties(
                widthSizing: extractLeafWidth(node.kind),
                heightSizing: extractLeafHeight(node.kind),
                layout: .horizontal,
                gap: 0,
                padding: .zero,
                justifyContent: .start,
                alignItems: .start,
                children: [],
                isContainer: false,
                textInput: extractTextInput(node),
                noteText: noteTextRequest(node),
                noteInsets: PenPostIt.bodyInsets(of: node)
            )
        }
    }

    static func extractTextInput(_ node: PenNode) -> TextMeasurementInput? {
        guard case let .text(data) = node.kind else { return nil }

        return TextMeasurementInput(
            request: PenTextMeasureRequest(
                text: data.content?.literalValue ?? "",
                fontFamily: data.fontFamily?.literalValue,
                fontSize: data.fontSize?.literalValue,
                fontWeight: data.fontWeight?.literalValue,
                fontStyle: data.fontStyle?.literalValue,
                letterSpacing: data.letterSpacing?.literalValue,
                lineHeight: data.lineHeight?.literalValue,
                runs: node.appliedRuns
            ),
            textGrowth: data.textGrowth
        )
    }

    static func extractLeafWidth(_ kind: PenNode.Kind) -> PenSizing {
        switch kind {
        case let .rectangle(d): d.width ?? .fitContent(fallback: nil)
        case let .ellipse(d): d.width ?? .fitContent(fallback: nil)
        case let .text(d): d.width ?? .fitContent(fallback: nil)
        case let .line(d): d.width ?? .fitContent(fallback: nil)
        case let .polygon(d): d.width ?? .fitContent(fallback: nil)
        case let .path(d): d.width ?? .fitContent(fallback: nil)
        case let .icon(d): d.width ?? .fitContent(fallback: nil)
        case let .script(d): d.width ?? .fitContent(fallback: nil)
        case let .browser(d): d.width ?? .fitContent(fallback: nil)
        case let .note(d): PenPostIt.layoutSizing(d.width)
        case let .prompt(d): PenPostIt.layoutSizing(d.width, default: PenPostIt.cardDefaultWidth)
        case let .context(d): PenPostIt.layoutSizing(d.width, default: PenPostIt.cardDefaultWidth)
        case let .unknown(_, properties): PenSizing(declared: properties["width"]) ?? .fitContent(fallback: nil)
        default: .fitContent(fallback: nil)
        }
    }

    static func extractLeafHeight(_ kind: PenNode.Kind) -> PenSizing {
        switch kind {
        case let .rectangle(d): d.height ?? .fitContent(fallback: nil)
        case let .ellipse(d): d.height ?? .fitContent(fallback: nil)
        case let .text(d): d.height ?? .fitContent(fallback: nil)
        case let .line(d): d.height ?? .fitContent(fallback: nil)
        case let .polygon(d): d.height ?? .fitContent(fallback: nil)
        case let .path(d): d.height ?? .fitContent(fallback: nil)
        case let .icon(d): d.height ?? .fitContent(fallback: nil)
        case let .script(d): d.height ?? .fitContent(fallback: nil)
        case let .browser(d): d.height ?? .fitContent(fallback: nil)
        case let .note(d): PenPostIt.layoutSizing(d.height)
        case let .prompt(d): PenPostIt.layoutSizing(d.height, default: PenPostIt.cardDefaultHeight)
        case let .context(d): PenPostIt.layoutSizing(d.height, default: PenPostIt.cardDefaultHeight)
        case let .unknown(_, properties): PenSizing(declared: properties["height"]) ?? .fitContent(fallback: nil)
        default: .fitContent(fallback: nil)
        }
    }
}
