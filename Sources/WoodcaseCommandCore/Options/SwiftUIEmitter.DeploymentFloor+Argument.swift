//
//  SwiftUIEmitter.DeploymentFloor+Argument.swift
//  WoodcaseCommandCore
//

import ArgumentParser
import Woodcase

/// `--floor ios18` on the command line: the raw values `ios26` and `ios18`, offered by
/// `--help` through `CaseIterable`.
extension SwiftUIEmitter.DeploymentFloor: ExpressibleByArgument {}
