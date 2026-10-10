//
//  FIFOQueue.swift
//  Woodcase
//

/// A first-in, first-out queue whose pops cost O(1), amortized.
///
/// `Array.removeFirst()` shifts every element left, so draining an array from the
/// front is quadratic; a follower replaying tens of thousands of rows spent most of its
/// time there. This keeps the array and an index to its head instead, and drops the
/// spent prefix only once it is at least half the storage.
struct FIFOQueue<Element> {
    /// Creates an empty queue.
    init() {}

    /// Whether nothing is waiting.
    var isEmpty: Bool {
        head == storage.count
    }

    /// How many elements are waiting.
    var count: Int {
        storage.count - head
    }

    /// The oldest waiting element, if any.
    var first: Element? {
        isEmpty ? nil : storage[head]
    }

    /// The waiting elements, oldest first.
    var elements: ArraySlice<Element> {
        storage[head...]
    }

    /// Adds an element at the back.
    ///
    /// - Parameter element: The element to add.
    mutating func append(_ element: Element) {
        storage.append(element)
    }

    /// Removes and returns the oldest element.
    ///
    /// - Returns: The oldest element, or `nil` when the queue is empty.
    mutating func popFirst() -> Element? {
        guard !isEmpty else { return nil }
        let element = storage[head]
        head += 1
        compact()
        return element
    }

    /// Removes up to `count` elements from the front.
    ///
    /// - Parameter count: How many to remove; fewer are removed when fewer are waiting.
    mutating func removeFirst(upTo count: Int) {
        head += Swift.max(0, Swift.min(count, self.count))
        compact()
    }

    // MARK: - Private

    private var storage: [Element] = []

    /// The index of the oldest waiting element in ``storage``.
    private var head = 0

    /// Drops the spent prefix once it is worth the copy: when the queue is empty, which
    /// is free, or when it is at least half the storage, which keeps every pop O(1)
    /// amortized.
    private mutating func compact() {
        if head == storage.count {
            storage.removeAll(keepingCapacity: true)
            head = 0
        } else if head >= 1024, head * 2 >= storage.count {
            storage.removeFirst(head)
            head = 0
        }
    }
}

extension FIFOQueue: Sendable where Element: Sendable {}

extension FIFOQueue: Equatable where Element: Equatable {
    /// Whether two queues hold the same waiting elements in the same order.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.elements.elementsEqual(rhs.elements)
    }
}

extension FIFOQueue: Hashable where Element: Hashable {
    /// Hashes the waiting elements in order.
    func hash(into hasher: inout Hasher) {
        hasher.combine(count)
        for element in elements {
            hasher.combine(element)
        }
    }
}

extension FIFOQueue: Codable where Element: Codable {
    /// Reads a queue back from its waiting elements, oldest first.
    init(from decoder: any Decoder) throws {
        storage = try [Element](from: decoder)
    }

    /// Writes the waiting elements, oldest first.
    func encode(to encoder: any Encoder) throws {
        try Array(elements).encode(to: encoder)
    }
}
