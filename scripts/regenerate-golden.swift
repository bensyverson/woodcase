#!/usr/bin/env swift
//
//  regenerate-golden.swift
//
//  Regenerates golden test files for ReactEmitter and ThemeEmitter.
//  Run from the repo root: swift scripts/regenerate-golden.swift
//
//  This script is a thin shell that builds and runs a test helper.
//  The actual regeneration happens in the test target since it has
//  access to Bundle.module and all the fixture resources.

import Foundation

// This script just invokes the test suite with UPDATE_GOLDEN=1 env var.
// The golden file tests check for this env var and overwrite instead of comparing.
print("To regenerate golden files, run:")
print("  UPDATE_GOLDEN=1 swift test --filter 'Golden'")
print("")
print("This will update all .golden files in Tests/WoodcaseTests/Fixtures/golden/")
