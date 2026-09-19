import Foundation

public extension String {
    /// Newer systems put a narrow no-break space before AM/PM; one kind of
    /// space keeps copy (and tests) predictable.
    var plainSpaces: String {
        replacingOccurrences(of: "\u{202F}", with: " ").replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
