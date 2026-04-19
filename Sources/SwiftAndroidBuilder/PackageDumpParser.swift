// PackageDumpParser.swift

import Foundation

/// Parses the JSON output of `swift package dump-package` to extract library product names.
public final class PackageDumpParser {

    /// Extracts library product names from `swift package dump-package` JSON output.
    /// Filters out executables and other non-library products.
    /// Returns sorted product names.
    public static func parseLibraryProductNames(from jsonString: String) throws -> [String] {
        let data = Data(jsonString.utf8)
        let dump = try JSONDecoder().decode(PackageDump.self, from: data)

        return dump.products
            .filter { $0.type.library != nil }
            .map(\.name)
            .sorted()
    }

    // MARK: - Private

    private init() {}
}

// MARK: - Private models

/// Lightweight model for decoding only the fields we need from dump-package output.
/// The full output has many more fields — we intentionally ignore them.
private struct PackageDump: Decodable {
    let products: [Product]

    struct Product: Decodable {
        let name: String
        let type: ProductType
    }

    struct ProductType: Decodable {
        let library: [String]?
        let executable: AnyCodable?

        enum CodingKeys: String, CodingKey {
            case library
            case executable
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            library = try container.decodeIfPresent([String].self, forKey: .library)
            // executable can be null or missing — we just check if library is present
            executable = nil
        }
    }
}

/// Placeholder for values we don't need to decode.
private struct AnyCodable: Decodable {}
