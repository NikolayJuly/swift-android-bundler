// MockShellExecutor.swift

import Foundation
import Logging
import SharedStructs

final class MockShellExecutor: ShellExecuting, @unchecked Sendable {

    /// Exact match: command key → output string.
    /// Key is formed by joining command array with spaces.
    var outputByCommand: [String: String] = [:]

    /// Regex match: checked when exact match not found.
    /// Checked in registration order, first match wins.
    private var patterns: [(regex: NSRegularExpression, output: String)] = []

    /// Commands that should throw an error.
    var failingCommands: Set<String> = []

    /// Register a regex pattern for command matching.
    func register(pattern: String, output: String) {
        let regex = try! NSRegularExpression(pattern: pattern)
        patterns.append((regex, output))
    }

    func execute(_ command: [String], logger: Logger) async throws -> String {
        let key = command.joined(separator: " ")

        if failingCommands.contains(key) {
            throw MockShellError.commandFailed(key)
        }

        // 1. Exact match
        if let output = outputByCommand[key] {
            return output
        }

        // 2. Regex match
        let range = NSRange(key.startIndex..., in: key)
        for (regex, output) in patterns {
            if regex.firstMatch(in: key, range: range) != nil {
                return output
            }
        }

        return ""
    }
}

enum MockShellError: Error {
    case commandFailed(String)
}
