import Foundation

enum SearchNormalizer {
    private static let locale = Locale(identifier: "en_US_POSIX")

    static func normalize(_ value: String) -> String {
        value
            .precomposedStringWithCompatibilityMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(with: locale)
    }
}
