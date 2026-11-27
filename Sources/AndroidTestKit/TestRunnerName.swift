// TestRunnerName.swift

/// How swiftbuild names the executable it makes for a test target.
package enum TestRunnerName {

    package static let suffix = "-test-runner"

    package static func runnerName(for testTarget: String) -> String {
        testTarget + suffix
    }
}
