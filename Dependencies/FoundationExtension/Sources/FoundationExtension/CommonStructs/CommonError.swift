// CommonError.swift
import Foundation

public enum CommonError: Error {
    case tooEarlyDeallocated(Sendable? = nil, _ file: String = #file, _ line: Int = #line)
}

public struct SimpleError: CustomStringConvertible, LocalizedError, CustomNSError {

    public init(_ description: String, file: String = #file, line: Int = #line) {
        self._description = description
        self.file = file
        self.line = line
    }

    public var errorDescription: String? {
        description
    }

    public var description: String {
        _description + " \(file):L\(line)"
    }

    // MARK: CustomNSError

    public static var errorDomain: String { "SimpleError" }

    public var errorCode: Int {
        "\(file):L\(line)".stableHash()
    }

    public var errorUserInfo: [String : Any] {
        return [NSLocalizedDescriptionKey: description]
    }

    // MARK: Private

    private let _description: String
    private let file: String
    private let line: Int
}

private extension String {
    // Took this hash from here: https://stackoverflow.com/questions/35882103/hash-value-of-string-that-would-be-stable-across-ios-releases
    func stableHash() -> Int {
            var result = Int (5381)
            let buf = [UInt8](utf8)
            for b in buf {
                result = 127 * (result & 0x00ffffffffffffff) + Int(b)
            }
            return result
    }
}
