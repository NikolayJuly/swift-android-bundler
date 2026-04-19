// PrintLogger.swift

import Logging

public struct PrintLogger: LogHandler {

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
        print(message)
    }
}
