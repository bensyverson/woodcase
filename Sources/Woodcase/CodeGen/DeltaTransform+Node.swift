//
//  DeltaTransform+Node.swift
//  Woodcase
//

extension DeltaTransform {
    /// The turn and flips a node's own properties give it: its literal rotation, and each
    /// flip that is literally `true`. A rotation bound to a variable is not resolved.
    init(of common: PenNodeCommon) {
        self.init(
            rotation: common.rotation?.literalValue,
            flipX: common.flipX?.literalValue == true,
            flipY: common.flipY?.literalValue == true
        )
    }
}
