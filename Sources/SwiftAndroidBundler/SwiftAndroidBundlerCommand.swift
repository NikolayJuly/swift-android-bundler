// SwiftAndroidBundlerCommand.swift

import ArgumentParser

@main
struct SwiftAndroidBundlerCommand: AsyncParsableCommand {

    static let configuration = CommandConfiguration(commandName: "swift-android-bundler",
                                                     abstract: "Toolkit for building and packaging Swift libraries for Android",
                                                     subcommands: [CollectCommand.self,
                                                                   BuildCommand.self,
                                                                   TestCommand.self])
}
