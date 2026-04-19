// AsyncShellCommand.swift
#if os(macOS) || os(Linux)

import Foundation
import Logging

public enum ShellCommandError: Error {
    case nonZeroCode(Int32, String?, String?) // status code, error, output
}

/// - note: This class execute commands, to execute script you need only`["-l"]` in `task.arguments`, so remove "-c"
public struct AsyncShellCommand: ~Copyable {

    /// - parameter command: command itself and arguments, for example ShellCommand(["ls", "-la"], ..)
    public init(_ command: [String],
                currentDirectoryURL: URL? = nil,
                environment: [String: String]? = nil,
                logger: Logger) {
        self.command = command
        self.currentDirectoryURL = currentDirectoryURL
        self.environment = environment
        self.logger = logger
    }

    /// - parameter command: command itself and arguments, for example ShellCommand("ls", "-la", ...)
    public init(_ command: String ...,
                currentDirectoryURL: URL? = nil,
                environment: [String: String]? = nil,
                logger: Logger) {
        self.command = command
        self.currentDirectoryURL = currentDirectoryURL
        self.environment = environment
        self.logger = logger
    }

    /// If no output - empty string will be returned
    @discardableResult
    public consuming func execute() async throws -> String {
        // If we have command part with space inside, but it is not wrapped with "", we will enforce it
        let wrappedCommand = command.map { commandPart in
            guard commandPart.contains(" ") else {
                return commandPart
            }

            let alreadyEscaped = commandPart.hasPrefix("\"") || commandPart.hasPrefix("'")
            guard !alreadyEscaped else {
                return commandPart
            }

            return "\"" + commandPart + "\""
        }

        let commandString = wrappedCommand.joined(separator: " ")
        let zShell = URL(fileURLWithPath: Self.shell)
        let command = ExecuteBinaryCommand(zShell,
                                           ["-c", "-l"] + [commandString],
                                           currentDirectoryURL: currentDirectoryURL,
                                           environment: environment,
                                           logger: logger)

        return try await command.execute()
    }

    // MARK: Private

    private let command: [String]
    private let currentDirectoryURL: URL?
    private let environment: [String: String]?
    private let logger: Logger

    private let lock = NSLock()
    private var didCompleteTask = false

    private var stdOut = [String]()
    private var errorOut = [String]()

    private static let shell: String = {
        if let shell = ProcessInfo.processInfo.environment["SHELL"] {
            return shell
        }
        #if os(macOS)
            return "/bin/zsh"
        #else
            return "/bin/bash"
        #endif
    }()
}

#endif // os(macOS) || os(Linux)
