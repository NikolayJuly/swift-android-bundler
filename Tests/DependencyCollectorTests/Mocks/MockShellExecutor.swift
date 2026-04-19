// MockShellExecutor.swift

import Foundation
import FoundationExtension
import Logging
import SharedStructs

final class MockShellExecutor: ShellExecuting, @unchecked Sendable {

    /// Mapping: binary file path → patchelf --print-needed output (newline-separated lib names).
    var patchelfOutputByPath: [String: String] = [:]

    func execute(_ command: [String], logger: Logger) async throws -> String {
        guard command.count >= 3,
              command[0] == "patchelf",
              command[1] == "--print-needed" else {
            throw SimpleError("MockShellExecutor: unexpected command: \(command.joined(separator: " "))")
        }
        let path = command[2]
        return patchelfOutputByPath[path] ?? ""
    }
}
