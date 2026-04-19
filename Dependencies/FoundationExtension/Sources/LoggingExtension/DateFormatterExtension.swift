// DateFormatterExtension.swift
import Foundation

package extension DateFormatter {
    static let loggerDateFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH-mm-ss'Z'"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.calendar = Calendar(identifier: .gregorian)
        return df
    }()
}
