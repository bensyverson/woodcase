//
//  PenLayoutEngine+Leaves.swift
//  Woodcase
//

import Foundation

// MARK: - Size Resolution

extension PenLayoutEngine {
    static func resolveIntrinsicSize(_ sizing: PenSizing, available: Double?) -> (size: Double, isFlexible: Bool, fallback: Double?) {
        switch sizing {
        case let .fixed(v):
            return (v, false, nil)
        case let .fitContent(fallback):
            return (fallback ?? 0, false, fallback)
        case let .fillContainer(fallback):
            if let available {
                return (available, true, fallback)
            }
            return (fallback ?? 0, true, fallback)
        case .variable:
            return (0, false, nil)
        }
    }

    static func resolveContainerSize(_ sizing: PenSizing, contentSize: Double, available: Double?) -> (size: Double, isFlexible: Bool, fallback: Double?) {
        switch sizing {
        case let .fixed(v):
            return (v, false, nil)
        case let .fitContent(fallback):
            let size = contentSize > 0 ? contentSize : (fallback ?? 0)
            return (size, false, fallback)
        case let .fillContainer(fallback):
            if let available {
                return (available, true, fallback)
            }
            // No parent to fill. If the author declared a fallback, honor it —
            // `fill_container(N)` means "use N when standalone." Otherwise fall
            // back to the measured content size.
            if let fallback {
                return (fallback, true, fallback)
            }
            return (contentSize, true, nil)
        case .variable:
            return (0, false, nil)
        }
    }
}

// MARK: - Leaves

extension PenLayoutEngine {
    /// The size of a node with no children: its declared sizes, or its text measured.
    ///
    /// - Parameters:
    ///   - props: The node's layout properties.
    ///   - availableWidth: The width its parent offers it.
    ///   - availableHeight: The height its parent offers it.
    ///   - textMeasurer: A function that measures text bounding boxes.
    /// - Returns: The node's size.
    static func layoutLeafNode(
        _ props: NodeLayoutProperties,
        availableWidth: Double?,
        availableHeight: Double?,
        textMeasurer: TextMeasurer
    ) -> (width: Double, height: Double) {
        // Resolve width first — text height may depend on it (wrapping)
        let (resolvedWidth, _, _) = resolveIntrinsicSize(props.widthSizing, available: availableWidth)

        if let noteText = props.noteText {
            let (setHeight, _, _) = resolveIntrinsicSize(props.heightSizing, available: availableHeight)
            let insets = props.noteInsets ?? PenPostIt.textInsets
            // A card drawn raw fits whichever of its two texts is taller, so it neither
            // jumps when editing starts nor clips its draft.
            let grown = [noteText, props.noteRawText].compactMap(\.self).map { text in
                grownNoteHeight(text, insets: insets, width: resolvedWidth, setHeight: setHeight, textMeasurer: textMeasurer)
            }.max() ?? setHeight
            return (resolvedWidth, grown)
        }

        // Check if text measurement can provide intrinsic sizing
        if let textInput = props.textInput,
           textInput.textGrowth != .fixedWidthHeight
        {
            let needsWidthFromText = props.widthSizing.isFitContent && textInput.textGrowth != .fixedWidth
            let needsHeightFromText = props.heightSizing.isFitContent

            let text = textInput.request.text
            if !text.isEmpty, needsWidthFromText || needsHeightFromText {
                // For width measurement: unconstrained unless width is already resolved
                let measureMaxWidth: Double? = needsWidthFromText ? nil : resolvedWidth

                var request = textInput.request
                request.maxWidth = measureMaxWidth
                let measured = textMeasurer(request)

                let w = needsWidthFromText ? measured.width : resolvedWidth
                let h = needsHeightFromText ? measured.height : resolveIntrinsicSize(props.heightSizing, available: availableHeight).size
                return (w, h)
            }

            // Empty text node: use one line height as the intrinsic height
            // so it still occupies vertical space in layout (matching Pen's behavior).
            if text.isEmpty, needsHeightFromText {
                let oneLineHeight = textMeasurer(textInput.request.measuring(" ", maxWidth: nil, runs: []))
                return (0, oneLineHeight.height)
            }
        }

        let (h, _, _) = resolveIntrinsicSize(props.heightSizing, available: availableHeight)
        return (resolvedWidth, h)
    }
}
