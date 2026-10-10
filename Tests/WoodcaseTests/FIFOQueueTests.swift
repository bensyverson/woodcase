//
//  FIFOQueueTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Pins ``FIFOQueue``, the follower's event buffer: first in, first out, through the
/// compactions that keep its pops O(1).
struct FIFOQueueTests {
    @Test("Elements come out in the order they went in, then nil")
    func popsInOrder() {
        var queue = FIFOQueue<Int>()
        #expect(queue.isEmpty)
        #expect(queue.popFirst() == nil)
        queue.append(1)
        queue.append(2)
        #expect(queue.first == 1)
        #expect(queue.popFirst() == 1)
        queue.append(3)
        #expect(queue.count == 2)
        #expect(queue.popFirst() == 2)
        #expect(queue.popFirst() == 3)
        #expect(queue.popFirst() == nil)
        #expect(queue.isEmpty)
    }

    @Test("Removing from the front removes at most what is waiting")
    func removeFirstUpTo() {
        var queue = FIFOQueue<Int>()
        for value in 0 ..< 5 {
            queue.append(value)
        }
        queue.removeFirst(upTo: 2)
        #expect(Array(queue.elements) == [2, 3, 4])
        queue.removeFirst(upTo: 10)
        #expect(queue.isEmpty)
        queue.removeFirst(upTo: 1)
        #expect(queue.count == 0)
        queue.append(9)
        #expect(queue.first == 9)
    }

    @Test("A long interleaving of appends and pops keeps its order across compactions")
    func orderSurvivesCompaction() {
        var queue = FIFOQueue<Int>()
        var expected: [Int] = []
        var next = 0
        for round in 0 ..< 50 {
            for _ in 0 ..< 300 {
                queue.append(next)
                next += 1
            }
            for _ in 0 ..< (round % 2 == 0 ? 250 : 340) {
                if let value = queue.popFirst() { expected.append(value) }
            }
        }
        while let value = queue.popFirst() {
            expected.append(value)
        }
        #expect(expected == Array(0 ..< next))
    }

    @Test("Two queues holding the same waiting elements are equal and hash alike")
    func equalityIgnoresSpentElements() throws {
        var spent = FIFOQueue<Int>()
        spent.append(0)
        spent.append(1)
        _ = spent.popFirst()
        var fresh = FIFOQueue<Int>()
        fresh.append(1)
        #expect(spent == fresh)
        #expect(spent.hashValue == fresh.hashValue)
        let decoded = try JSONDecoder().decode(FIFOQueue<Int>.self, from: JSONEncoder().encode(spent))
        #expect(decoded == fresh)
    }
}
