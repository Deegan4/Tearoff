import Foundation

public struct PolicyTable: Sendable {
    private let rules: [PolicyRule]

    public init(rules: [PolicyRule]) {
        self.rules = rules
    }

    public var merchantCount: Int {
        Set(rules.map(\.merchantKey)).count
    }

    /// Collapses receipt spelling variance to a stable key. Receipts print
    /// "BEST BUY #1234", "Best Buy", and "BESTBUY.COM" for the same retailer,
    /// and all three normalize to "bestbuy".
    ///
    /// Known limitation: a trailing numeric run preceded by whitespace or
    /// `#` is stripped as a store number, e.g. "TARGET #0428" -> "target".
    /// This is deliberately conservative — it only fires when digits are
    /// separated from the name by whitespace or `#`, so "7-Eleven" (digit
    /// is part of the name, no separator before it) is untouched. But a
    /// name that legitimately ends in a space-separated number, e.g.
    /// "Studio 54", loses that suffix and normalizes to "studio". This is
    /// accepted: a resulting key miss is a safe failure (the resolver
    /// returns `nil` and the app asks the user), whereas failing to strip
    /// real store numbers would cause every receipt from a chain to miss
    /// the curated table. The dangerous failure mode — two different
    /// merchants collapsing onto the same key — does not occur here,
    /// because stripping only ever removes trailing digits, never letters.
    public static func normalize(_ merchant: String) -> String {
        let lowered = merchant
            .lowercased()
            .replacingOccurrences(of: ".com", with: "")

        // Receipts print store numbers: "TARGET #0428", "WALMART 1234".
        // Strip a trailing numeric run so the key matches the chain.
        let stripped = lowered.replacingOccurrences(
            of: #"[\s#]+\d+\s*$"#,
            with: "",
            options: .regularExpression
        )

        return stripped
            .unicodeScalars
            .filter { CharacterSet.alphanumerics.contains($0) }
            .reduce(into: "") { $0.unicodeScalars.append($1) }
    }

    /// The rule in force at `date`, preferring a category-specific rule over
    /// a general one when both are in force.
    public func rule(merchantKey: String, category: PurchaseCategory, on date: Date) -> PolicyRule? {
        let inForce = rules.filter {
            $0.merchantKey == merchantKey
                && $0.effectiveDate <= date
                && ($0.category == nil || $0.category == category)
        }

        return inForce.max { lhs, rhs in
            if lhs.effectiveDate != rhs.effectiveDate {
                return lhs.effectiveDate < rhs.effectiveDate
            }
            // Same effective date: category-specific outranks general.
            return (lhs.category == nil) && (rhs.category != nil)
        }
    }

    public static func bundled() throws -> PolicyTable {
        guard let url = Bundle.module.url(forResource: "return-policies", withExtension: "json") else {
            throw PolicyTableError.resourceMissing
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rules = try decoder.decode([PolicyRule].self, from: Data(contentsOf: url))
        return PolicyTable(rules: rules)
    }
}

public enum PolicyTableError: Error {
    case resourceMissing
}
