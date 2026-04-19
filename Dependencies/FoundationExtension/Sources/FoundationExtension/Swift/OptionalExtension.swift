// OptionalExtension.swift
import Foundation

public extension Optional {

    @inlinable
    func unwrapped(_ message: String = "", file: String = #file, function: String = #function, line: Int = #line) throws -> Wrapped {
        guard case let .some(value) = self else {
            throw OptionalExtensionError.optionIsNil(message: message, file: file, function: function, line: line)
        }

        return value
    }
}

public enum OptionalExtensionError: LocalizedError {
    case optionIsNil(message: String = "", file: String = #file, function: String = #function, line: Int = #line)

    public var errorDescription: String? {
        switch self {
        case let .optionIsNil(message, file, function, line):
            let updatedMessage = message.isEmpty ? "" : ". Message: \(message)"
            return "Failed to unwrap in \(file), function: \(function), line: \(line)\(updatedMessage)"
        }
    }
}
