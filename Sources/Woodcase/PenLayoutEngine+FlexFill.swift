//
//  PenLayoutEngine+FlexFill.swift
//  Woodcase
//

import Foundation

/// How a flex container fills its `fill_container` children, on both axes.
///
/// A fill always sizes the child's **unturned** box: the main-axis share fills its unturned
/// width (or height), the container's inner cross size its unturned height (or width).
/// The container then allocates, aligns and fits the bounds of the turned result, as it
/// does for any turned child — so a turned fill child can take more room than its share,
/// and a cross-axis fill's turn can change how much room it takes on the main axis. This
/// is Pen's settled layout (`project/2026-09-28-geometry-model.md`, divergences 1–2).
extension PenLayoutEngine.FlexLayout {
    // MARK: - Main axis

    /// The least a `fill_container` child gets on the main axis: Pen gives a fill 1 pt when
    /// its siblings and gaps leave it less, overflowing or not, and places the next child
    /// after it (`flex-fill-squeeze.pen`, `PenFlexFillMinimumTests`).
    static let minimumFillMain = 1.0

    /// Resolves the container's main size and each `fill_container` child's share.
    mutating func beginFilling() {
        totalGaps = props.gap * Double(max(0, flowChildren.count - 1))
        // A turned cross-axis fill's main extent depends on the cross size it fills, so
        // it is settled before the share is: exactly when the container's cross size is
        // known up front, else from the siblings that set it.
        let provisionalCross = availableCrossForChildren ?? measurements
            .filter { !$0.isFlexibleMain && !$0.isFlexibleCross }
            .map(\.crossSize)
            .max() ?? 0
        for index in measurements.indices where measurements[index].isFlexibleCross && !measurements[index].isFlexibleMain {
            fillCross(of: index, with: provisionalCross)
        }
        let totalFixedMain = resolveOwnMain()

        let fillCount = measurements.filter(\.isFlexibleMain).count
        let remainingMain = mainContentSize - totalFixedMain - totalGaps
        fillMainSize = fillCount > 0 ? max(Self.minimumFillMain, remainingMain / Double(fillCount)) : 0

        phase = .filling
        next = 0
    }

    /// Resolves the container's own main size from its children's main extents.
    ///
    /// - Returns: The main extent of the children that do not fill the main axis.
    @discardableResult
    mutating func resolveOwnMain() -> Double {
        let totalFixedMain = measurements.filter { !$0.isFlexibleMain }.reduce(0.0) { $0 + $1.mainSize }
        let mainPadding = isHorizontal ? props.padding.horizontal : props.padding.vertical
        (ownMain, _, _) = PenLayoutEngine.resolveContainerSize(
            isHorizontal ? props.widthSizing : props.heightSizing,
            contentSize: totalFixedMain + totalGaps + mainPadding,
            available: isHorizontal ? call.availableWidth : call.availableHeight
        )
        mainContentSize = ownMain - mainPadding
        return totalFixedMain
    }

    /// Asks for the next `fill_container` child, sized with its share.
    mutating func nextFillingCall() -> PenLayoutEngine.LayoutFrame.Call? {
        while next < measurements.count, !measurements[next].isFlexibleMain {
            next += 1
        }
        guard next < measurements.count else { return nil }
        measurements[next].mainSize = fillMainSize
        return PenLayoutEngine.LayoutFrame.Call(
            node: measurements[next].node,
            availableWidth: isHorizontal ? fillMainSize : nil,
            availableHeight: isHorizontal ? nil : fillMainSize,
            target: scratch,
            usesCache: false
        )
    }

    /// Takes a `fill_container` child's size as sized with its share: that is its
    /// unturned box, and its turned bounds are the room it takes.
    mutating func absorbFill(_ childSize: (width: Double, height: Double)) {
        measurements[next].measuredWidth = childSize.width
        measurements[next].measuredHeight = childSize.height
        let turned = PenLayoutEngine.applyRotationExpansion(
            width: childSize.width, height: childSize.height, node: measurements[next].node
        )
        measurements[next].mainSize = isHorizontal ? turned.width : turned.height
        if !measurements[next].isFlexibleCross {
            measurements[next].crossSize = isHorizontal ? turned.height : turned.width
        }
    }

    // MARK: - Cross axis

    /// Fills every cross-axis `fill_container` child with the container's inner cross
    /// size, and fits the container's main size again if that moved any child's main
    /// extent.
    ///
    /// Only a turned child's main extent can move, and only when a main-axis fill sibling,
    /// not the measured ones, set the cross size. The fill shares are not taken again then:
    /// that would need the fills sized a second time.
    mutating func fillCrossAxis() {
        let mainExtents = measurements.map(\.mainSize)
        for index in measurements.indices where measurements[index].isFlexibleCross {
            fillCross(of: index, with: crossContentSize)
            measurements[index].crossSize = isHorizontal
                ? turnedSize(of: measurements[index]).height
                : turnedSize(of: measurements[index]).width
        }
        if measurements.map(\.mainSize) != mainExtents {
            resolveOwnMain()
        }
    }

    /// Gives a cross-axis fill child's unturned box the cross size it fills, and takes
    /// the main extent of its turned bounds.
    ///
    /// - Parameters:
    ///   - index: The child's index in `measurements`.
    ///   - cross: The container's inner cross size.
    private mutating func fillCross(of index: Int, with cross: Double) {
        if isHorizontal {
            measurements[index].measuredHeight = cross
        } else {
            measurements[index].measuredWidth = cross
        }
        let turned = turnedSize(of: measurements[index])
        measurements[index].mainSize = isHorizontal ? turned.width : turned.height
    }

    /// The bounds of a measured child's unturned box, turned.
    private func turnedSize(of measurement: PenLayoutEngine.ChildMeasurement) -> (width: Double, height: Double) {
        PenLayoutEngine.applyRotationExpansion(
            width: measurement.measuredWidth, height: measurement.measuredHeight, node: measurement.node
        )
    }
}
