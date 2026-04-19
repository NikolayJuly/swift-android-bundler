// ConsoleLogger.swift
import Foundation
import Logging

public struct ConsoleLogger: LogHandler {

    public init() {}

    // MARK: LogHandler

    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get {
            metadata[key]
        }
        set {
            metadata[key] = newValue
        }
    }
    
    public var metadata: Logger.Metadata = [:]

    public var logLevel: Logger.Level = .info

    public func log(level: Logger.Level,
                    message: Logger.Message,
                    metadata: Logger.Metadata?,
                    source: String,
                    file: String,
                    function: String,
                    line: UInt) {
        // TODO: find place to add function in prefix
        let prefixNeededLevels: [Logger.Level] = [.warning, .error]

        var prefix: String = ""
        if prefixNeededLevels.contains(level) {
            prefix = "\(file): line \(line) :: "
        }

        let dateString = DateFormatter.loggerDateFormatter.string(from: Date())
        let resString = dateString + " [\(level)] \(prefix)\(message)"
        print(resString)
    }
}

