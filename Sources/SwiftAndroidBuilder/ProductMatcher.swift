// ProductMatcher.swift

import Foundation
import FoundationExtension

/// Matches product names to source packages.
public final class ProductMatcher {

    public struct MatchedProduct: Sendable {
        public let product: String
        public let packagePath: URL

        public init(product: String, packagePath: URL) {
            self.product = product
            self.packagePath = packagePath
        }
    }

    public struct SourcePackage: Sendable {
        public let path: URL
        public let productNames: [String]

        public init(path: URL, productNames: [String]) {
            self.path = path
            self.productNames = productNames
        }
    }

    /// Matches each product name to a source package that contains it.
    /// - Throws: if any product is not found or found in multiple sources.
    /// - Returns: dictionary of product name → matched result
    public static func match(products: [String],
                             sources: [SourcePackage]) throws -> [String: MatchedProduct] {
        var result: [String: MatchedProduct] = [:]

        for product in products {
            let matchingSources = sources.filter { $0.productNames.contains(product) }

            switch matchingSources.count {
            case 0:
                let availableProducts = sources.flatMap(\.productNames).sorted()
                throw SimpleError("Product '\(product)' not found in any source package. Available products: \(availableProducts.joined(separator: ", "))")
            case 1:
                result[product] = MatchedProduct(product: product,
                                                  packagePath: matchingSources[0].path)
            default:
                let paths = matchingSources.map { $0.path.fileSystemPath }.joined(separator: ", ")
                throw SimpleError("Product '\(product)' found in multiple source packages: \(paths)")
            }
        }

        return result
    }

    // MARK: - Private

    private init() {}
}
