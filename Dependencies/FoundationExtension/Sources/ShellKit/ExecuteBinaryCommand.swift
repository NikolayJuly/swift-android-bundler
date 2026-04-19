// ExecuteBinaryCommand.swift
#if os(macOS) || os(Linux)

import Foundation
import Logging

public struct ExecuteBinaryCommand: ~Copyable, @unchecked Sendable {
    /// - parameter binary: path to a binary
    public init(_ binary: URL,
                _ arguments: [String],
                currentDirectoryURL: URL? = nil,
                environment: [String: String]? = nil,
                logger: Logger) {
        self.binary = binary
        self.arguments = arguments
        self.currentDirectoryURL = currentDirectoryURL
        self.environment = environment
        self.logger = logger
    }

    public init(_ binary: URL,
                _ arguments: String ...,
                currentDirectoryURL: URL? = nil,
                environment: [String: String]? = nil,
                logger: Logger) {
        self.binary = binary
        self.arguments = arguments
        self.currentDirectoryURL = currentDirectoryURL
        self.environment = environment
        self.logger = logger
    }

    /// If no output - empty string will be returned
    @discardableResult
    public consuming func execute() async throws -> String {
        let task = Process()
        self.task = task

        let pipe = Pipe()
        let errorPipe = Pipe()

        // If we have command part with space inside, but it is not wrapped with "", we will enforce it
        let wrappedArguments = arguments.map { commandPart in
            guard commandPart.contains(" ") else {
                return commandPart
            }

            let alreadyEscaped = commandPart.hasPrefix("\"") || commandPart.hasPrefix("''")
            guard !alreadyEscaped else {
                return commandPart
            }

            return "\"" + commandPart + "\""
        }

        let commandString = wrappedArguments.joined(separator: " ")
        if let currentDirectoryURL {
            logger.info("Executing command in directory: \(currentDirectoryURL.path)")
        }
        if let environment {
            logger.info("Command environment:\n\(environment.map { $0.key + ":" + $0.value }.joined(separator: "\n"))")
        }
        logger.info("Executing command: \(binary.path) \(commandString)")

        task.standardOutput = pipe
        task.standardError = errorPipe
        task.arguments = arguments
        task.executableURL = binary
        task.standardInput = nil

        if let currentDirectoryURL {
            task.currentDirectoryURL = currentDirectoryURL
        }

        if let environment {
            task.environment = environment
        }

        let stdOutLines = AsyncBytesToLines()
        let errOutLines = AsyncBytesToLines()

        pipe.fileHandleForReading.readabilityHandler = { fileHandler in
            let availableData = fileHandler.availableData
            guard availableData.isEmpty == false else {
                stdOutLines.complete()
                fileHandler.readabilityHandler = nil
                return
            }
            stdOutLines.add(availableData)
        }

        errorPipe.fileHandleForReading.readabilityHandler = { fileHandler in
            let availableData = fileHandler.availableData
            guard availableData.isEmpty == false else {
                errOutLines.complete()
                fileHandler.readabilityHandler = nil
                return
            }
            errOutLines.add(availableData)
        }

        let stdOutputTask = Task { @Sendable [logger] in
            for await line in stdOutLines {
                guard line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    continue
                }
                logger.info("\(line)")
            }
        }

        let errorOutputTask = Task { @Sendable [logger] in
            for await line in errOutLines {
                guard line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
                    continue
                }
                logger.error("\(line)")
            }
        }

        try await withCheckedThrowingContinuation { [task] continuation in
            task.terminationHandler = { _ in
                continuation.resume()
            }

            do {
                try task.run()
            } catch {
                logger.error("Failed to run task with error - \(error)")
                continuation.resume(throwing: error)
            }
        }

        // Process terminated. Drain remaining pipe data and finalize streams.
        // On Linux, readabilityHandler EOF callback may not fire before
        // terminationHandler, so we drain manually to prevent deadlock
        // and avoid losing tail output.
        pipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil

        let remainingStdout = pipe.fileHandleForReading.readDataToEndOfFile()
        if remainingStdout.isEmpty == false {
            stdOutLines.add(remainingStdout)
        }
        let remainingStderr = errorPipe.fileHandleForReading.readDataToEndOfFile()
        if remainingStderr.isEmpty == false {
            errOutLines.add(remainingStderr)
        }

        stdOutLines.complete()
        errOutLines.complete()

        _ = await (stdOutputTask.value, errorOutputTask.value)

        let output = stdOutLines.currentLines().joined(separator: "\n")

        guard task.terminationStatus == 0 else {
            let errorOutput = errOutLines.currentLines().joined(separator: "\n")
            throw ShellCommandError.nonZeroCode(task.terminationStatus, errorOutput, output)
        }

        return output
    }

    public func terminate() {
        task?.terminate()
    }

    // MARK: Private

    private let binary: URL
    private let arguments: [String]
    private let currentDirectoryURL: URL?
    private let environment: [String: String]?
    private let logger: Logger

    private let lock = NSLock()
    private var didCompleteTask = false

    private var task: Process?
}

#endif // os(macOS) || os(Linux)
