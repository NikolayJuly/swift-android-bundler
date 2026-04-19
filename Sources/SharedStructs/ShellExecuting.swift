// ShellExecuting.swift

import Logging
import ShellKit

public protocol ShellExecuting: Sendable {
    func execute(_ command: [String], logger: Logger) async throws -> String
}

/// Production implementation — delegates to AsyncShellCommand.
public struct AsyncShellExecutor: ShellExecuting {

    public init() {}

    public func execute(_ command: [String], logger: Logger) async throws -> String {
        try await AsyncShellCommand(command, logger: logger).execute()
    }
}
