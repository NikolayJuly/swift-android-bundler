// RecordingShellExecutor.swift

import Foundation
import Logging
import SharedStructs
import ShellKit

final class RecordingShellExecutor: ShellExecuting, @unchecked Sendable {

    private(set) var commands: [[String]] = []

    /// A command whose joined text contains the key fails with that exit code.
    var exitCodeByFragment: [String: Int32] = [:]

    func execute(_ command: [String], logger: Logger) async throws -> String {
        commands.append(command)
        let text = command.joined(separator: " ")
        for (fragment, code) in exitCodeByFragment where text.contains(fragment) {
            throw ShellCommandError.nonZeroCode(code, nil, nil)
        }
        return ""
    }
}
