//
//  GeneratedFileTests.swift
//  Woodcase
//

import Foundation
import Testing
@testable import Woodcase

@Suite("GeneratedFile")
struct GeneratedFileTests {
    @Test("Default write policy is .always")
    func defaultWritePolicy() {
        let file = GeneratedFile(path: "test.tsx", content: "content")
        #expect(file.writePolicy == .always)
    }

    @Test("Explicit scaffoldOnce policy is preserved")
    func scaffoldOncePolicy() {
        let file = GeneratedFile(path: "package.json", content: "{}", writePolicy: .scaffoldOnce)
        #expect(file.writePolicy == .scaffoldOnce)
    }

    @Test("WritePolicy conforms to Friendly")
    func writePolicyIsFriendly() {
        let policy = GeneratedFile.WritePolicy.scaffoldOnce
        let encoded = try? JSONEncoder().encode(policy)
        #expect(encoded != nil)
        if let data = encoded {
            let decoded = try? JSONDecoder().decode(GeneratedFile.WritePolicy.self, from: data)
            #expect(decoded == policy)
        }
    }
}
