//
//  SwiftUIEmitter+Options.swift
//  Woodcase
//

public extension SwiftUIEmitter {
    /// Options controlling SwiftUI code generation.
    struct Options: Friendly {
        /// The oldest OS releases the emitted package supports.
        public var deploymentFloor: DeploymentFloor

        /// The Swift module (and package, and library product) the files belong to:
        /// `Sources/<moduleName>/…`. It must be a Swift identifier.
        public var moduleName: String

        /// Creates options; the defaults are the iOS 26 floor and a module named `PenUI`.
        public init(deploymentFloor: DeploymentFloor = .iOS26, moduleName: String = "PenUI") {
            self.deploymentFloor = deploymentFloor
            self.moduleName = moduleName
        }
    }
}
