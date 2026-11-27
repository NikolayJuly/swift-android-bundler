// TestsRunnerTests.swift

import FileSystemKit
import Foundation
import FoundationExtension
import LoggingExtension
import ShellKit
import Testing

@testable import AndroidTestKit

@Suite("TestsRunner")
struct TestsRunnerTests {

    /// Scenario: two runners, two libraries. The folder is pushed once, each runner made executable,
    /// then every runner runs with xctest first and with swift-testing after.
    @Test
    func runsEveryRunnerWithEveryLibrary() async throws {
        let context = try Context(files: ["ATests-test-runner", "ATests.so", "BTests-test-runner", "libswiftCore.so"])

        try await context.run(libraries: [.xctest, .swiftTesting])

        let commands = context.shell.commands.map { $0.joined(separator: " ") }
        #expect(commands == [
            Context.adbShell("'rm' '-rf' '/data/local/tmp/tests'"),
            "adb push /output/tests/ /data/local/tmp/tests/",
            Context.adbShell("'chmod' '+x' '/data/local/tmp/tests/ATests-test-runner'"),
            Context.adbShell("'chmod' '+x' '/data/local/tmp/tests/BTests-test-runner'"),
            Context.runCommand(runner: "ATests-test-runner", library: "xctest"),
            Context.runCommand(runner: "BTests-test-runner", library: "xctest"),
            Context.runCommand(runner: "ATests-test-runner", library: "swift-testing"),
            Context.runCommand(runner: "BTests-test-runner", library: "swift-testing"),
        ])
    }

    /// The device command sets the environment before the runner, puts the device folder ahead of a given
    /// LD_LIBRARY_PATH, and passes the extra arguments to the runner as they are.
    @Test
    func deviceCommandCarriesEnvironmentAndArguments() async throws {
        let context = try Context(files: ["NetTests-test-runner"])

        try await context.run(libraries: [.swiftTesting],
                              environment: [(name: "ANDROID_ROOT", value: "/system"),
                                            (name: "LD_LIBRARY_PATH", value: "/apex/lib64")],
                              runnerArguments: ["--filter", "A|B"])

        let deviceCommand = try #require(context.deviceCommands.last)
        let expected = "cd '/data/local/tmp/tests' && ANDROID_ROOT='/system' "
            + "LD_LIBRARY_PATH='/data/local/tmp/tests:/apex/lib64' "
            + "'./NetTests-test-runner' '--testing-library' 'swift-testing' '--filter' 'A|B'"
        #expect(deviceCommand == expected)
    }

    /// A runner that exits with 69 (no tests for this library) is skipped and the run goes on.
    @Test
    func skipsRunnerWithoutTests() async throws {
        let context = try Context(files: ["ATests-test-runner", "BTests-test-runner"])
        context.shell.exitCodeByFragment["./ATests-test-runner"] = 69

        try await context.run(libraries: [.swiftTesting])

        #expect(context.deviceCommands.last?.contains("BTests-test-runner") == true)
    }

    /// When no runner has tests for a library, the run fails, as the single package bundle did.
    @Test
    func throwsWhenNoRunnerHasTests() async throws {
        let context = try Context(files: ["ATests-test-runner"])
        context.shell.exitCodeByFragment["--testing-library"] = 69

        await #expect(throws: SimpleError.self) {
            try await context.run(libraries: [.swiftTesting])
        }
    }

    /// A failing runner stops the run with its own error.
    @Test
    func rethrowsFailedRunner() async throws {
        let context = try Context(files: ["ATests-test-runner", "BTests-test-runner"])
        context.shell.exitCodeByFragment["./ATests-test-runner"] = 1

        await #expect(throws: ShellCommandError.self) {
            try await context.run(libraries: [.xctest])
        }
        #expect(context.deviceCommands.contains { $0.contains("./BTests-test-runner") } == false)
    }

    /// A folder without runners fails before anything reaches the device.
    @Test
    func throwsWhenFolderHasNoRunners() async throws {
        let context = try Context(files: ["libswiftCore.so"])

        await #expect(throws: SimpleError.self) {
            try await context.run(libraries: [.xctest])
        }
        #expect(context.shell.commands.isEmpty)
    }

    // MARK: - Private

    private final class Context {

        let fileSystem = InMemoryFileSystemService(rootUrl: URL(filePath: "/"),
                                                   appRootContainer: URL(filePath: "/app"))
        let shell = RecordingShellExecutor()
        let folder = URL(filePath: "/output/tests", directoryHint: .isDirectory)

        init(files: [String]) throws {
            try fileSystem.createAllSubfolders(upTo: folder, in: URL(filePath: "/"))
            for file in files {
                try fileSystem.write(data: Data("elf".utf8),
                                     to: folder.appending(path: file, directoryHint: .notDirectory))
            }
        }

        /// Device-side text of every `adb shell` call, with the local quoting taken off.
        var deviceCommands: [String] {
            shell.commands
                .filter { $0.count == 3 && $0[0] == "adb" && $0[1] == "shell" }
                .map { Self.unquoted($0[2]) }
        }

        static func runCommand(runner: String, library: String) -> String {
            let device = "cd '/data/local/tmp/tests' && LD_LIBRARY_PATH='/data/local/tmp/tests' "
                + "'./\(runner)' '--testing-library' '\(library)'"
            return adbShell(device)
        }

        /// `adb shell` joined as the recorder sees it, with the device command quoted for the local shell.
        static func adbShell(_ deviceCommand: String) -> String {
            "adb shell " + quoted(deviceCommand)
        }

        func run(libraries: [TestingLibrary],
                 environment: [(name: String, value: String)] = [],
                 runnerArguments: [String] = []) async throws {
            let runner = TestsRunner(shellExecutor: shell,
                                     fileSystemService: fileSystem,
                                     logger: .silent)
            try await runner.run(folder: folder,
                                 libraries: libraries,
                                 environment: environment,
                                 runnerArguments: runnerArguments)
        }

        private static func quoted(_ text: String) -> String {
            "'" + text.replacing("'", with: "'\\''") + "'"
        }

        private static func unquoted(_ text: String) -> String {
            String(text.dropFirst().dropLast()).replacing("'\\''", with: "'")
        }
    }
}
