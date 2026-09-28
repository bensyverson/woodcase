//
//  PenNodeCommon.swift
//  Woodcase
//
//  Created by Claude on 2026-03-22.
//

import Foundation

/// Shared properties common to all .pen node types.
///
/// These correspond to the base Entity properties in the .pen format spec.
/// Every node carries these regardless of its `type`.
public struct PenNodeCommon: Friendly {
    public init(
        name: String? = nil,
        x: PenValue<Double>? = nil,
        y: PenValue<Double>? = nil,
        rotation: PenValue<Double>? = nil,
        opacity: PenValue<Double>? = nil,
        enabled: PenValue<Bool>? = nil,
        flipX: PenValue<Bool>? = nil,
        flipY: PenValue<Bool>? = nil,
        reusable: Bool? = nil,
        theme: [String: String]? = nil,
        context: String? = nil,
        layoutPosition: PenLayoutPosition? = nil,
        metadata: PenMetadata? = nil
    ) {
        self.name = name
        self.x = x
        self.y = y
        self.rotation = rotation
        self.opacity = opacity
        self.enabled = enabled
        self.flipX = flipX
        self.flipY = flipY
        self.reusable = reusable
        self.theme = theme
        self.context = context
        self.layoutPosition = layoutPosition
        self.metadata = metadata
    }

    public var name: String?
    public var x: PenValue<Double>?
    public var y: PenValue<Double>?
    public var rotation: PenValue<Double>?
    public var opacity: PenValue<Double>?
    public var enabled: PenValue<Bool>?
    public var flipX: PenValue<Bool>?
    public var flipY: PenValue<Bool>?
    public var reusable: Bool?
    public var theme: [String: String]?
    public var context: String?
    public var layoutPosition: PenLayoutPosition?
    public var metadata: PenMetadata?
}
