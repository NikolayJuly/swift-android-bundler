// TestCommand.swift

import ArgumentParser

struct TestCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(commandName: "test",
                                                     abstract: "Collect a package's Android test runners and run them on a device",
                                                     subcommands: [TestCollectCommand.self,
                                                                   TestRunCommand.self])
}
