//
//  PenScaleRoundingTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// The rounding a proportional scale keeps, public so an editor that sizes a node another
/// way (Penumbra's note resize) writes the values a scale writes (leaf ERbzdG).
struct PenScaleRoundingTests {
    @Test("A length is kept to a hundredth of a point")
    func lengthToHundredths() {
        #expect(PenScaleRounding.length(13, by: 1.2345) == 16.05)
        #expect(PenScaleRounding.length(10, by: 1.5) == 15)
        #expect(PenScaleRounding.length(-2, by: 1.111) == -2.22)
    }

    @Test("A length that is not zero is never rounded to nothing, on either side of it")
    func lengthNeverZero() {
        #expect(PenScaleRounding.length(0.1, by: 0.01) == 0.01)
        #expect(PenScaleRounding.length(-0.1, by: 0.01) == -0.01)
        #expect(PenScaleRounding.length(0, by: 2) == 0)
    }

    @Test("A factor is kept to four decimals")
    func factorToFourDecimals() {
        #expect(PenScaleRounding.factor(1, by: 20.0 / 13.0) == 1.5385)
        #expect(PenScaleRounding.factor(2, by: 1.5) == 3)
    }

    @Test("A factor above zero stays above zero; zero stays zero")
    func factorNeverZero() {
        #expect(PenScaleRounding.factor(0.5, by: 0.00001) == 0.0001)
        #expect(PenScaleRounding.factor(0, by: 3) == 0)
    }

    @Test("The precisions are a hundredth and four decimals")
    func precisions() {
        #expect(PenScaleRounding.lengthPrecision == 100)
        #expect(PenScaleRounding.factorPrecision == 10000)
    }

    @Test("The scaler rounds through the same rule")
    func scalerAgrees() {
        let scaler = ProportionalScaler(factor: 0.01)
        #expect(scaler.scaled(-0.1) == PenScaleRounding.length(-0.1, by: 0.01))
        #expect(scaler.factor(.double(0.5)) == ProportionalScaler.number(PenScaleRounding.factor(0.5, by: 0.01)))
    }
}
