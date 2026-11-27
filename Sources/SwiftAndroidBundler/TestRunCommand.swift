// TestRunCommand.swift

import AndroidTestKit
import ArgumentParser
import FileSystemKit
import Foundation
import Logging
import LoggingExtension
import SharedStructs

extension TestingLibrary: ExpressibleByArgument {}

struct TestRunCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(commandName: "run",
                                                     abstract: "Push collected test runners to the device over adb and run every runner",
                                                     discussion: "Arguments after -- go to every runner, e.g. -- --no-parallel --filter 'Suite'.")

    @Argument(help: "Folder made by `test collect`.")
    var folder: String

    @Option(name: .customLong("testing-library"),
            help: "Testing library to run: xctest, swift-testing (can be repeated).")
    var testingLibraries: [TestingLibrary]

    @Option(name: .customLong("env"),
            help: "NAME=value set for every runner (can be repeated). LD_LIBRARY_PATH goes after the device folder.")
    var environment: [String] = []

    @Argument(parsing: .postTerminator,
              help: "Arguments for every runner.")
    var runnerArguments: [String] = []

    // MARK: - AsyncParsableCommand

    func validate() throws {
        guard testingLibraries.isEmpty == false else {
            throw ValidationError("Give at least one --testing-library.")
        }
        for assignment in environment where assignment.contains("=") == false {
            throw ValidationError("--env '\(assignment)' is not NAME=value.")
        }
    }

    func run() async throws {
        let logger = Logger(label: "TestRun", factory: { _ in ConsoleLogger() })
        let parsedEnvironment = environment.map { assignment in
            let parts = assignment.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            return (name: String(parts[0]), value: String(parts[1]))
        }

        let runner = TestsRunner(shellExecutor: AsyncShellExecutor(),
                                 fileSystemService: FileManager.default,
                                 logger: logger)
        let folderUrl = URL(filePath: folder, directoryHint: .isDirectory)
        try await runner.run(folder: folderUrl,
                             libraries: testingLibraries,
                             environment: parsedEnvironment,
                             runnerArguments: runnerArguments)
    }
}
