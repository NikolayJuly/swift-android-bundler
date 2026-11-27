// TestsRunner.swift

import FileSystemKit
import Foundation
import FoundationExtension
import Logging
import SharedStructs
import ShellKit

package enum TestingLibrary: String, CaseIterable, Sendable {
    case xctest
    case swiftTesting = "swift-testing"
}

/// Pushes a folder of collected test runners to the device over adb and runs each runner with each library.
package final class TestsRunner {

    package init(shellExecutor: some ShellExecuting,
                 fileSystemService: FileSystemService,
                 logger: Logger) {
        self.shellExecutor = shellExecutor
        self.fileSystemService = fileSystemService
        self.logger = logger
    }

    // MARK: - Package

    package static let deviceFolder = "/data/local/tmp/tests"

    /// - Parameter environment: set for every runner; an `LD_LIBRARY_PATH` goes after the device folder.
    /// - Parameter runnerArguments: passed to every runner after `--testing-library`.
    /// - Throws: on a failed runner, or when a library has no tests in any runner.
    package func run(folder: URL,
                     libraries: [TestingLibrary],
                     environment: [(name: String, value: String)],
                     runnerArguments: [String]) async throws {
        let runners = try runnerNames(in: folder)
        guard runners.isEmpty == false else {
            throw SimpleError("No test runners in \(folder.fileSystemPath)")
        }
        logger.info("Test runners: \(runners.joined(separator: ", "))")

        let device = Self.deviceFolder
        try await adbShell(Self.quotedWords(["rm", "-rf", device]))
        // A trailing slash on both sides: the folder's content lands in the device folder, not a copy of the folder.
        let localPath = folder.fileSystemPath
        let source = localPath.hasSuffix("/") ? localPath : localPath + "/"
        _ = try await shellExecutor.execute(["adb", "push", source, device + "/"], logger: logger)
        for runner in runners {
            try await adbShell(Self.quotedWords(["chmod", "+x", device + "/" + runner]))
        }

        let assignments = environmentAssignments(environment)
        for library in libraries {
            var ranAny = false
            for runner in runners {
                logger.info("=== \(runner): \(library.rawValue) ===")
                let invocation = Self.quotedWords(["./" + runner, "--testing-library", library.rawValue] + runnerArguments)
                let command = "cd \(Self.shellQuoted(device)) && \(assignments) \(invocation)"
                let didRun = try await runTests(command)
                if didRun {
                    ranAny = true
                } else {
                    logger.info("No \(library.rawValue) tests in \(runner)")
                }
            }
            guard ranAny else {
                throw SimpleError("No \(library.rawValue) tests in any runner of \(folder.fileSystemPath)")
            }
        }
    }

    // MARK: - Private

    /// Swift Testing exits with EX_UNAVAILABLE when a runner has no tests, e.g. a Darwin-only target on Android.
    private static let noTestsExitCode: Int32 = 69

    private let shellExecutor: any ShellExecuting
    private let fileSystemService: FileSystemService
    private let logger: Logger

    private func runnerNames(in folder: URL) throws -> [String] {
        let (files, _) = try fileSystemService.categorizedFolderContent(at: folder)
        return files
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(TestRunnerName.suffix) }
            .sorted()
    }

    /// `NAME='value' …` for the device shell; only the value is quoted, or the word stops being an assignment.
    private func environmentAssignments(_ environment: [(name: String, value: String)]) -> String {
        let device = Self.deviceFolder
        let libraryPath = environment.first { $0.name == "LD_LIBRARY_PATH" }
        let fullLibraryPath = libraryPath.map { device + ":" + $0.value } ?? device
        let others = environment.filter { $0.name != "LD_LIBRARY_PATH" }
        let all = others + [(name: "LD_LIBRARY_PATH", value: fullLibraryPath)]
        return all
            .map { $0.name + "=" + Self.shellQuoted($0.value) }
            .joined(separator: " ")
    }

    /// - Returns: `false` when the runner had no tests to run.
    private func runTests(_ command: String) async throws -> Bool {
        do {
            try await adbShell(command)
            return true
        } catch let ShellCommandError.nonZeroCode(code, _, _) where code == Self.noTestsExitCode {
            return false
        }
    }

    /// Runs a device shell command; quoted once more for the local shell that starts adb.
    private func adbShell(_ command: String) async throws {
        _ = try await shellExecutor.execute(["adb", "shell", Self.shellQuoted(command)], logger: logger)
    }

    private static func quotedWords(_ words: [String]) -> String {
        words
            .map { shellQuoted($0) }
            .joined(separator: " ")
    }

    private static func shellQuoted(_ word: String) -> String {
        "'" + word.replacing("'", with: "'\\''") + "'"
    }
}
