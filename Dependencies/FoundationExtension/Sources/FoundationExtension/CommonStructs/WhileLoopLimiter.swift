// WhileLoopLimiter.swift
import Foundation

/// This struct helps to prevent infinite loop, but applying limit on number of while loops
///
///  Sample code:
///
///  ```
///     let limiter = WhileLoopLimiter(limit: 100)
///     while limiter.startNextLoop() {
///         // do your things...
///     }
///
///     if limiter.didDrainLimit {
///         // report to logger about the error
///     }
///  ```
///
public final class WhileLoopLimiter {

    public init(limit: Int) {
        self.limit = limit
    }

    public func startNextLoop() -> Bool {
        guard limit > 0 else {
            assertionFailure("We did hit limit on execution of while loop. Probably there is a bug.")
            return false
        }

        limit -= 1
        return true
    }

    public var didDrainLimit: Bool {
        limit <= 0
    }

    // MARK: Private

    private var limit: Int
}
