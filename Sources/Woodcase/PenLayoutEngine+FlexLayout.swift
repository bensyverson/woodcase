//
//  PenLayoutEngine+FlexLayout.swift
//  Woodcase
//

import Foundation

extension PenLayoutEngine {
    /// A flex container — a frame with a horizontal or vertical layout — part-way
    /// through being laid out.
    ///
    /// The algorithm runs in four passes, each of which may stop to have a child sized
    /// and resume with its size:
    ///
    /// 1. **Measuring.** Every flow child whose main axis is not `fill_container` is
    ///    sized into the scratch map, offered the pre-resolved cross axis so a wrapping
    ///    text knows its width.
    /// 2. **Filling.** The container's main size is resolved, the space left over is
    ///    shared among the `fill_container` children, and each is sized again with its
    ///    share. The scratch map is then copied into the target.
    ///    A fill sizes the child's unturned box; a turned child takes the bounds of the
    ///    result (`PenLayoutEngine+FlexFill.swift`).
    /// 3. **Arranging.** The cross size is resolved and filled, `justifyContent` and `alignItems`
    ///    place each flow child, and a container that fills the cross axis is laid out
    ///    again at its resolved size — the only arrangement that writes new rects.
    /// 4. **Placing absolute children** at their own x/y.
    ///
    /// Disabled nodes (`enabled == false`) take no part at all, matching Pen, where
    /// hidden elements take no space.
    struct FlexLayout {
        /// Which pass the container is in.
        enum Phase {
            case measuring, filling, arranging, placingAbsolute
        }

        /// The call this container answers.
        let call: LayoutFrame.Call

        /// The container's layout properties.
        let props: NodeLayoutProperties

        /// The store the measuring passes write to, owned by this container.
        let scratch: Int

        /// Whether the main axis is horizontal.
        let isHorizontal: Bool

        /// The enabled children in the flow.
        let flowChildren: [PenNode]

        /// The enabled children positioned absolutely.
        let absoluteChildren: [PenNode]

        /// The cross-axis content size offered to measured children, when the container
        /// knows its own cross size before measuring.
        let availableCrossForChildren: Double?

        /// The pass in progress.
        var phase = Phase.measuring

        /// The index of the child in progress within the pass's list.
        var next = 0

        /// Every flow child measured so far.
        var measurements: [ChildMeasurement] = []

        /// The gaps between flow children, in total.
        var totalGaps = 0.0

        /// The container's own main-axis size.
        var ownMain = 0.0

        /// The main-axis size inside the padding.
        var mainContentSize = 0.0

        /// The main-axis size each `fill_container` child gets.
        var fillMainSize = 0.0

        /// The container's own cross-axis size.
        var ownCross = 0.0

        /// The cross-axis size inside the padding.
        var crossContentSize = 0.0

        /// The distance between consecutive flow children.
        var spacing = 0.0

        /// Where the next flow child starts on the main axis.
        var mainCursor = 0.0

        /// Starts laying out a flex container.
        ///
        /// - Parameters:
        ///   - call: The call the container answers.
        ///   - props: Its layout properties.
        ///   - scratch: The store its measuring passes write to.
        init(call: LayoutFrame.Call, props: NodeLayoutProperties, scratch: Int) {
            self.call = call
            self.props = props
            self.scratch = scratch
            isHorizontal = props.layout == .horizontal

            let enabledChildren = props.children.filter { $0.common.enabled?.literalValue != false }
            flowChildren = enabledChildren.filter { $0.common.layoutPosition != .absolute }
            absoluteChildren = enabledChildren.filter { $0.common.layoutPosition == .absolute }

            // Pre-resolve the cross-axis size so fill_container children can use it
            // (e.g. text wrapping needs the available width in a vertical layout)
            let crossSizingSelf = isHorizontal ? props.heightSizing : props.widthSizing
            let crossAvailSelf = isHorizontal ? call.availableHeight : call.availableWidth
            let (preResolvedCross, _, _) = PenLayoutEngine.resolveIntrinsicSize(crossSizingSelf, available: crossAvailSelf)
            let crossPaddingPre = isHorizontal ? props.padding.vertical : props.padding.horizontal
            availableCrossForChildren = preResolvedCross > 0 ? preResolvedCross - crossPaddingPre : nil
        }

        /// Runs the passes until a child needs sizing, or the container is done.
        ///
        /// - Parameters:
        ///   - size: The size of the child the last step asked for, or `nil`.
        ///   - stores: The walk's rect maps.
        /// - Returns: The next child to size, or the container's own size.
        mutating func advance(
            resuming size: (width: Double, height: Double)?,
            stores: inout [[String: PenRect]]
        ) -> LayoutFrame.Step {
            var size = size
            while true {
                switch phase {
                case .measuring:
                    if let measured = size {
                        measurements.append(measurement(of: flowChildren[next], measured: measured))
                        next += 1
                        size = nil
                    }
                    if let child = nextMeasuringCall() { return .call(child) }
                    beginFilling()

                case .filling:
                    if let measured = size {
                        absorbFill(measured)
                        next += 1
                        size = nil
                    }
                    if let child = nextFillingCall() { return .call(child) }
                    // Container arrangement can skip every child that does not fill
                    // the cross axis: its descendants' rects are right from measuring.
                    stores[call.target].merge(stores[scratch]) { _, new in new }
                    beginArranging()

                case .arranging:
                    if size != nil {
                        place(measurements[next], into: &stores)
                        next += 1
                        size = nil
                    }
                    if let child = nextArrangingCall(stores: &stores) { return .call(child) }
                    phase = .placingAbsolute
                    next = 0

                case .placingAbsolute:
                    if let measured = size {
                        let child = absoluteChildren[next]
                        stores[call.target][child.id] = PenLayoutEngine.freeRect(
                            of: child,
                            x: child.common.x?.literalValue ?? 0,
                            y: child.common.y?.literalValue ?? 0,
                            size: measured,
                            placedIn: stores[call.target]
                        )
                        next += 1
                        size = nil
                    }
                    if let child = nextAbsoluteCall(stores: &stores) { return .call(child) }
                    return .done(
                        width: isHorizontal ? ownMain : ownCross,
                        height: isHorizontal ? ownCross : ownMain
                    )
                }
            }
        }

        // MARK: - Measuring

        /// A child's sizings along this container's axes.
        private func axes(of child: PenNode) -> (
            mainFlex: Bool, mainFallback: Double?, crossSize: Double, crossFlex: Bool, crossFallback: Double?
        ) {
            let childProps = PenLayoutEngine.extractLayoutProperties(child)
            let mainSizing = isHorizontal ? childProps.widthSizing : childProps.heightSizing
            let crossSizing = isHorizontal ? childProps.heightSizing : childProps.widthSizing
            let (_, mainFlex, mainFallback) = PenLayoutEngine.resolveIntrinsicSize(mainSizing, available: nil)
            let (crossSize, crossFlex, crossFallback) = PenLayoutEngine.resolveIntrinsicSize(crossSizing, available: nil)
            return (mainFlex, mainFallback, crossSize, crossFlex, crossFallback)
        }

        /// Records every `fill_container` child up to the next one to measure, and asks
        /// for that one — sized into the scratch map, uncached, and offered the resolved
        /// cross-axis content size so a fill_container grandchild resolves correctly.
        private mutating func nextMeasuringCall() -> LayoutFrame.Call? {
            while next < flowChildren.count {
                let child = flowChildren[next]
                let axes = axes(of: child)
                guard axes.mainFlex else {
                    return LayoutFrame.Call(
                        node: child,
                        availableWidth: isHorizontal ? nil : availableCrossForChildren,
                        availableHeight: isHorizontal ? availableCrossForChildren : nil,
                        target: scratch,
                        usesCache: false
                    )
                }
                measurements.append(ChildMeasurement(
                    node: child,
                    mainSize: 0,
                    crossSize: axes.crossSize,
                    isFlexibleMain: true,
                    isFlexibleCross: axes.crossFlex,
                    mainFallback: axes.mainFallback,
                    crossFallback: axes.crossFallback,
                    measuredWidth: 0,
                    measuredHeight: 0
                ))
                next += 1
            }
            return nil
        }

        /// The measurement of a child that was sized, expanded to its rotated bounding
        /// box on both axes.
        private func measurement(of child: PenNode, measured raw: (width: Double, height: Double)) -> ChildMeasurement {
            let axes = axes(of: child)
            let childSize = PenLayoutEngine.applyRotationExpansion(width: raw.width, height: raw.height, node: child)
            let crossSize = isHorizontal ? childSize.height : childSize.width
            return ChildMeasurement(
                node: child,
                mainSize: isHorizontal ? childSize.width : childSize.height,
                crossSize: axes.crossFlex ? 0 : crossSize,
                isFlexibleMain: false,
                isFlexibleCross: axes.crossFlex,
                mainFallback: axes.mainFallback,
                crossFallback: axes.crossFallback,
                measuredWidth: raw.width,
                measuredHeight: raw.height
            )
        }

        // MARK: - Arranging

        /// Resolves the cross size and the main-axis start and spacing.
        private mutating func beginArranging() {
            let crossPadding = isHorizontal ? props.padding.vertical : props.padding.horizontal
            let maxChildCross = measurements.map(\.crossSize).max() ?? 0
            (ownCross, _, _) = PenLayoutEngine.resolveContainerSize(
                isHorizontal ? props.heightSizing : props.widthSizing,
                contentSize: maxChildCross + crossPadding,
                available: isHorizontal ? call.availableHeight : call.availableWidth
            )
            crossContentSize = ownCross - crossPadding
            fillCrossAxis()

            let totalChildrenMain = measurements.reduce(0.0) { $0 + $1.mainSize }
            let freeSpace = max(0, mainContentSize - (totalChildrenMain + totalGaps))
            let mainStart: Double
            (mainStart, spacing) = justification(freeSpace: freeSpace)
            mainCursor = (isHorizontal ? props.padding.left : props.padding.top) + mainStart

            phase = .arranging
            next = 0
        }

        /// Where the flow starts on the main axis and how far apart children sit, for
        /// the container's `justifyContent`.
        private func justification(freeSpace: Double) -> (start: Double, spacing: Double) {
            switch props.justifyContent {
            case .start:
                return (0, props.gap)
            case .center:
                return (freeSpace / 2, props.gap)
            case .end:
                return (freeSpace, props.gap)
            case .spaceBetween:
                guard flowChildren.count > 1 else { return (0, props.gap) }
                return (0, props.gap + freeSpace / Double(flowChildren.count - 1))
            case .spaceAround:
                guard !flowChildren.isEmpty else { return (0, props.gap) }
                let chunk = freeSpace / Double(flowChildren.count)
                return (chunk / 2, props.gap + chunk)
            }
        }

        /// Places flow children until a container that fills the cross axis needs
        /// laying out again at its resolved size, and asks for it.
        ///
        /// Only such a container is laid out again: its resolved cross size may differ
        /// from its measurement. Every other container's descendant rects are already
        /// in the target, from the scratch merge. A child's own children lay out in its
        /// unrotated rect — the bounding-box expansion is only how much space it takes
        /// in this container.
        private mutating func nextArrangingCall(stores: inout [[String: PenRect]]) -> LayoutFrame.Call? {
            while next < measurements.count {
                let measurement = measurements[next]
                let isContainer = switch measurement.node.kind {
                case .frame, .group: true
                default: false
                }
                if isContainer, measurement.isFlexibleCross {
                    let placed = placement(of: measurement)
                    return LayoutFrame.Call(
                        node: measurement.node,
                        availableWidth: placed.unrotatedWidth,
                        availableHeight: placed.unrotatedHeight,
                        target: call.target,
                        usesCache: call.usesCache
                    )
                }
                place(measurement, into: &stores)
                next += 1
            }
            return nil
        }

        /// Writes a flow child's rect and moves the cursor past it.
        private mutating func place(_ measurement: ChildMeasurement, into stores: inout [[String: PenRect]]) {
            stores[call.target][measurement.node.id] = placement(of: measurement).rect
            mainCursor += measurement.mainSize + spacing
        }

        /// A flow child's rect at the cursor, and the unrotated size its own children
        /// lay out in.
        private func placement(of measurement: ChildMeasurement) -> (
            rect: PenRect, unrotatedWidth: Double, unrotatedHeight: Double
        ) {
            let crossPaddingStart = isHorizontal ? props.padding.top : props.padding.left
            let crossOffset: Double = switch props.alignItems {
            case .start: crossPaddingStart
            case .center: crossPaddingStart + (crossContentSize - measurement.crossSize) / 2
            case .end: crossPaddingStart + crossContentSize - measurement.crossSize
            }

            // A rotated child's measurement kept its pre-rotation size, so it is not
            // sized again for it, and its rect carries that size to whatever draws it.
            let rotation = measurement.node.common.rotation?.literalValue ?? 0
            let unturned = rotation == 0
                ? nil
                : PenSize(width: measurement.measuredWidth, height: measurement.measuredHeight)
            let rect = isHorizontal
                ? PenRect(
                    x: mainCursor, y: crossOffset, width: measurement.mainSize, height: measurement.crossSize,
                    unturnedSize: unturned
                )
                : PenRect(
                    x: crossOffset, y: mainCursor, width: measurement.crossSize, height: measurement.mainSize,
                    unturnedSize: unturned
                )
            let drawn = rect.drawnSize
            return (rect, drawn.width, drawn.height)
        }

        // MARK: - Absolute Children

        /// Places absolute children until one needs sizing, and asks for it.
        private mutating func nextAbsoluteCall(stores: inout [[String: PenRect]]) -> LayoutFrame.Call? {
            while next < absoluteChildren.count {
                let child = absoluteChildren[next]
                let x = child.common.x?.literalValue ?? 0
                let y = child.common.y?.literalValue ?? 0
                if PenLayoutEngine.tryShortCircuitFixedLeaf(child, x: x, y: y, into: &stores[call.target]) != nil {
                    next += 1
                    continue
                }
                return LayoutFrame.Call(
                    node: child, availableWidth: nil, availableHeight: nil,
                    target: call.target, usesCache: call.usesCache
                )
            }
            return nil
        }
    }
}
