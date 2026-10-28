//
//  PenFill+ShaderFill.swift
//  Woodcase
//

import Foundation

public extension PenFill {
    /// A GPU fragment shader fill.
    ///
    /// Woodcase preserves shader fills losslessly but never executes them: the
    /// renderer treats a shader fill as fully transparent, and the React
    /// emitter emits no background for it.
    struct PenShaderFill: Friendly {
        public init(
            enabled: PenValue<Bool>? = nil,
            blendMode: PenBlendMode? = nil,
            opacity: PenValue<Double>? = nil,
            url: String,
            uniforms: PenShaderUniforms? = nil,
            extras: PenExtras = PenExtras()
        ) {
            self.enabled = enabled
            self.blendMode = blendMode
            self.opacity = opacity
            self.url = url
            self.uniforms = uniforms
            self.extras = extras
        }

        public var enabled: PenValue<Bool>?
        public var blendMode: PenBlendMode?
        public var opacity: PenValue<Double>?
        /// The shader file's URL, relative to the .pen file (e.g. `"effect.glsl"`).
        public var url: String
        /// Named uniform values passed to the shader, the same type a shader effect's take.
        public var uniforms: PenShaderUniforms?

        /// Keys the file wrote on this fill that the model does not claim. See ``PenExtras``.
        public var extras = PenExtras()

        /// The keys this payload claims; any other key of its object is an extra.
        enum CodingKeys: String, CodingKey, CaseIterable {
            case enabled, blendMode, opacity, url, uniforms
        }
    }
}
