//
//  StackHighWater.swift
//  WoodcaseTests
//

#if canImport(Darwin)
    import Darwin

    /// How deep into its stack a piece of work reaches, measured without letting it
    /// overflow.
    ///
    /// Swift concurrency runs a task on a cooperative-pool thread with 512 KiB of stack,
    /// and a debug build of a recursive walk can use kilobytes per level. Running the
    /// work on a thread of that size would tell a regression apart only by killing the
    /// test process. Instead the work runs on a thread whose stack this type owns: the
    /// memory is painted with a pattern first, and whatever the work overwrote is how
    /// much it used. A guard page below the stack turns a runaway into a crash rather
    /// than a scribble; the default 64 MiB is far above any budget a test asserts, so
    /// even a badly regressed walk reports a number instead of killing the run.
    enum StackHighWater {
        /// The stack a Swift task gets on Apple platforms.
        static let taskStackSize = 512 * 1024

        /// The byte the unused stack is painted with.
        private static let paint: UInt8 = 0xA5

        /// Runs `work` on a fresh thread and reports the most stack it used.
        ///
        /// - Parameters:
        ///   - stackSize: The stack the thread gets; a multiple of the page size.
        ///   - work: The work to measure.
        /// - Returns: The bytes of stack the deepest call reached, and the work's result.
        static func measure<T>(stackSize: Int = 64 * 1024 * 1024, _ work: @escaping () -> T) -> (bytes: Int, result: T) {
            let page = Int(getpagesize())
            let mapped = stackSize + page
            guard let base = mmap(nil, mapped, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANON, -1, 0),
                  base != MAP_FAILED
            else { fatalError("could not map a stack of \(stackSize) bytes") }
            defer { munmap(base, mapped) }
            mprotect(base, page, PROT_NONE)
            let stack = base + page
            memset(stack, Int32(paint), stackSize)

            let box = ResultBox<T>()
            let runner = Runner { box.value = work() }
            var attributes = pthread_attr_t()
            pthread_attr_init(&attributes)
            defer { pthread_attr_destroy(&attributes) }
            pthread_attr_setstack(&attributes, stack, stackSize)

            var thread: pthread_t?
            let context = Unmanaged.passRetained(runner).toOpaque()
            let status = pthread_create(&thread, &attributes, { context in
                Unmanaged<Runner>.fromOpaque(context).takeRetainedValue().body()
                return nil
            }, context)
            guard status == 0, let thread else { fatalError("pthread_create failed: \(status)") }
            pthread_join(thread, nil)

            let bytes = stack.assumingMemoryBound(to: UInt8.self)
            var untouched = 0
            while untouched < stackSize, bytes[untouched] == paint {
                untouched += 1
            }
            guard let result = box.value else { fatalError("the measured work did not finish") }
            return (stackSize - untouched, result)
        }

        /// The work, type-erased: a C thread entry point cannot capture a generic type.
        private final class Runner {
            let body: () -> Void

            init(_ body: @escaping () -> Void) {
                self.body = body
            }
        }

        /// The work's result, written on the measured thread and read after the join.
        private final class ResultBox<T> {
            var value: T?
        }
    }
#endif
