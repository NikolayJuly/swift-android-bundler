// LoggerExtension.swift
import Logging

public extension Logger {

    static let silent = Logger(label: "Silent", factory: { _ in SilentLogger() })

    func debug(_ message: String,
               metadata: @autoclosure () -> Logger.Metadata? = nil,
               source: @autoclosure () -> String? = nil,
               file: String = #fileID, function: String = #function, line: UInt = #line) {
        let message = Logger.Message(stringLiteral: message)
        debug(message, metadata: metadata(), source: source(), file: file, function: function, line: line)
    }

    func info(_ message: String,
              metadata: @autoclosure () -> Logger.Metadata? = nil,
              source: @autoclosure () -> String? = nil,
              file: String = #fileID, function: String = #function, line: UInt = #line) {
        let message = Logger.Message(stringLiteral: message)
        info(message, metadata: metadata(), source: source(), file: file, function: function, line: line)
    }

    func error(_ message: String,
               metadata: @autoclosure () -> Logger.Metadata? = nil,
               source: @autoclosure () -> String? = nil,
               file: String = #fileID, function: String = #function, line: UInt = #line) {
        let message = Logger.Message(stringLiteral: message)
        error(message, metadata: metadata(), source: source(), file: file, function: function, line: line)
    }
}
