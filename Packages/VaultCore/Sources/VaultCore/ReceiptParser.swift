import Foundation

/// Heuristic receipt parser. Deliberately conservative: it never invents a
/// value it cannot find in the text. Duration/policy is still resolved by
/// VaultCore from the merchant + category, not guessed here.
public enum ReceiptParser {
    public static func parse(_ lines: [String]) -> ParsedReceipt {
        // Lowercased full text, reused by the keyword/phrase detectors below.
        let hay = lines.joined(separator: "\n").lowercased()
        // Return/warranty terms are often spelled out ("one year warranty",
        // "thirty day returns"). Bridge cardinals to digits so the numeric
        // detectors below catch them; only used for those two scans.
        let numericHay = spellOutToDigits(hay)
        return ParsedReceipt(
            merchant: merchant(from: lines),
            date: date(from: lines),
            totalCents: total(from: lines),
            category: category(in: hay),
            printedReturnDays: returnDays(in: numericHay),
            printedWarrantyMonths: warrantyMonths(in: numericHay),
            subtotalCents: labeledAmount("subtotal", in: lines),
            taxCents: labeledAmount("tax", in: lines, excluding: ["subtotal"]),
            paymentMethod: paymentMethod(in: lines),
            orderNumber: orderNumber(in: lines),
            lineItems: lineItems(in: lines)
        )
    }

    // MARK: Amount breakdown — a labelled subtotal / tax line.

    private static func labeledAmount(_ keyword: String, in lines: [String], excluding: [String] = []) -> Cents? {
        for line in lines {
            let lower = line.lowercased()
            guard lower.contains(keyword),
                  !excluding.contains(where: { lower.contains($0) }) else { continue }
            if let amount = amounts(in: line).last { return Cents(amount) }
        }
        return nil
    }

    // MARK: Payment method — a card brand (+ last four) or cash.

    private static func paymentMethod(in lines: [String]) -> String? {
        let brands: [(needle: String, label: String)] = [
            ("american express", "Amex"), ("amex", "Amex"), ("mastercard", "Mastercard"),
            ("visa", "Visa"), ("discover", "Discover"), ("debit", "Debit"),
            ("credit", "Credit"), ("cash", "Cash"),
        ]
        for line in lines {
            let lower = line.lowercased()
            guard let brand = brands.first(where: { lower.contains($0.needle) }) else { continue }
            if brand.label == "Cash" { return "Cash" }
            if let last4 = lastFourDigits(in: line) { return "\(brand.label) ••••\(last4)" }
            return brand.label
        }
        return nil
    }

    /// The card's last four: prefer digits after a mask (`****1234`,
    /// `ending in 1234`), else a lone trailing 4-digit group.
    private static func lastFourDigits(in line: String) -> String? {
        for pattern in [#"(?:\*{2,}|x{2,}|ending(?:\s+in)?\s+)(\d{4})"#, #"(\d{4})(?!\d)"#] {
            if let group = firstGroup(pattern, in: line) { return group }
        }
        return nil
    }

    // MARK: Order / transaction number.

    private static func orderNumber(in lines: [String]) -> String? {
        let pattern = #"(?:order|transaction|trans|receipt|invoice|ref|auth)[^0-9A-Za-z]{0,6}#?\s*([0-9A-Za-z][0-9A-Za-z\-]{3,})"#
        for line in lines {
            let lower = line.lowercased()
            guard ["order", "transaction", "trans", "receipt", "invoice", "ref", "auth"]
                .contains(where: { lower.contains($0) }) else { continue }
            // Require at least one digit so plain words aren't mistaken for IDs.
            if let id = firstGroup(pattern, in: line), id.contains(where: \.isNumber) {
                return id
            }
        }
        return nil
    }

    // MARK: Line items — a name followed by a trailing price.

    private static func lineItems(in lines: [String]) -> [LineItem] {
        // Lines that are really labels/totals/tender, not products.
        let skip = ["total", "subtotal", "tax", "change", "cash", "card", "balance",
                    "tip", "gratuity", "saving", "discount", "visa", "mastercard",
                    "amex", "debit", "credit", "order", "transaction", "receipt",
                    "ref", "invoice", "auth", "points", "reward", "thank", "member"]
        var items: [LineItem] = []
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let lower = line.lowercased()
            if skip.contains(where: { lower.contains($0) }) { continue }
            // Must end with a price token.
            guard let priceRange = line.range(of: #"\d{1,3}(?:,\d{3})*\.\d{2}\s*$"#, options: .regularExpression),
                  let price = amounts(in: line).last, price > 0 else { continue }
            var name = String(line[..<priceRange.lowerBound])
                .trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "-*•·. \t"))
            // Collapse internal whitespace runs.
            name = name.replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            let letters = name.filter(\.isLetter).count
            guard letters >= 2, (2...40).contains(name.count) else { continue }
            items.append(LineItem(name: name, cents: price))
            if items.count >= 40 { break }
        }
        return items
    }

    /// First capture group of `pattern` as a String (preserves leading zeros).
    private static func firstGroup(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    // MARK: Merchant — first line that reads like a name.

    private static func merchant(from lines: [String]) -> String {
        for raw in lines {
            let line = raw.trimmingCharacters(in: .whitespaces)
            let letters = line.filter(\.isLetter).count
            let digits = line.filter(\.isNumber).count
            // A store name is mostly letters, a few chars long, not an address
            // line (which is digit-heavy) or a phone number.
            if letters >= 3, digits == 0, line.count <= 40 {
                return normalizeName(line)
            }
        }
        // Fall back to the first non-empty line.
        return normalizeName(lines.first { !$0.trimmingCharacters(in: .whitespaces).isEmpty } ?? "")
    }

    private static func normalizeName(_ s: String) -> String {
        // Strip OCR leading/trailing noise: quote marks, bullets, arrows like
        // ">", stray punctuation — anything that isn't a letter or digit at
        // either end. Interior characters (e.g. "H&M", "7-Eleven") are kept.
        let edges = CharacterSet.alphanumerics.inverted
        let trimmed = s
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: edges)
        // Collapse ALL-CAPS shouting into Title Case for a tidy slip.
        if trimmed == trimmed.uppercased() && trimmed.contains(where: \.isLetter) {
            return trimmed.capitalized
        }
        return trimmed
    }

    // MARK: Total — prefer a line labelled TOTAL, else the largest amount.

    private static func total(from lines: [String]) -> Cents? {
        var labelled: [Int] = []
        var all: [Int] = []

        for line in lines {
            let lower = line.lowercased()
            let amounts = amounts(in: line)
            all.append(contentsOf: amounts)
            // "total" but not "subtotal" / "total savings" / "total tax".
            if lower.contains("total"),
               !lower.contains("subtotal"),
               !lower.contains("saving"),
               !lower.contains("tax") {
                labelled.append(contentsOf: amounts)
            }
        }

        if let best = labelled.max() { return Cents(best) }
        if let best = all.max() { return Cents(best) }
        return nil
    }

    /// All currency-looking amounts in a line, as integer cents.
    private static func amounts(in line: String) -> [Int] {
        let pattern = #"\d{1,3}(?:,\d{3})*\.\d{2}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(line.startIndex..., in: line)
        return regex.matches(in: line, range: range).compactMap { match in
            guard let r = Range(match.range, in: line) else { return nil }
            let token = line[r].replacingOccurrences(of: ",", with: "")
            let parts = token.split(separator: ".")
            guard parts.count == 2,
                  let dollars = Int(parts[0]),
                  let cents = Int(parts[1]) else { return nil }
            return dollars * 100 + cents
        }
    }

    // MARK: Date — first parseable date token.

    private static func date(from lines: [String]) -> Date? {
        let numeric = #"\d{1,2}[/-]\d{1,2}[/-]\d{2,4}"#
        let named = #"(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)[a-z]*\.?\s+\d{1,2},?\s+\d{2,4}"#
        let formats = ["MM/dd/yyyy", "MM/dd/yy", "M/d/yyyy", "M/d/yy",
                       "MM-dd-yyyy", "MM-dd-yy", "MMM d yyyy", "MMM d, yyyy",
                       "MMMM d yyyy", "MMMM d, yyyy"]

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")

        for line in lines {
            for pattern in [numeric, named] {
                guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                      let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
                      let r = Range(match.range, in: line) else { continue }
                let token = String(line[r])
                for format in formats {
                    formatter.dateFormat = format
                    if let parsed = formatter.date(from: token) {
                        // Reject nonsense far-future dates from OCR noise.
                        if parsed <= Date().addingTimeInterval(60 * 60 * 24) {
                            return parsed
                        }
                    }
                }
            }
        }
        return nil
    }

    // MARK: Category — keyword/merchant buckets, first confident hit wins.

    /// Returns a category only when the text clearly signals one, so an
    /// ambiguous receipt keeps the form's default instead of a bad guess.
    private static func category(in hay: String) -> PurchaseCategory? {
        // Ordered most-specific first: a pharmacy inside a grocery store
        // should read as pharmacy, fuel before the station's convenience
        // items, etc.
        let buckets: [(PurchaseCategory, [String])] = [
            (.pharmacy,      ["pharmacy", "prescription", "walgreens", "cvs", "rite aid", "rx#", "rx #"]),
            (.fuel,          ["unleaded", "diesel", "gallons", "regular gal", "pump ", "fuel ", "shell", "chevron", "exxon", "mobil ", "76 station"]),
            (.restaurant,    ["restaurant", "gratuity", "server:", "server ", "dine-in", "dine in", "guest count", "table "]),
            (.groceries,     ["grocery", "supermarket", "safeway", "kroger", "trader joe", "whole foods", "aldi", "food lion", "publix"]),
            (.electronics,   ["best buy", "electronics", "apple store", "geek squad", "micro center", "laptop", "gpu "]),
            (.appliances,    ["appliance", "refrigerator", "dishwasher", "washer/dryer"]),
            (.tools,         ["home depot", "lowe's", "lowes", "harbor freight", "ace hardware", "hardware"]),
            (.furniture,     ["ikea", "furniture", "mattress", "ashley home", "wayfair"]),
            (.apparel,       ["old navy", "h&m", "nordstrom", "apparel", "clothing", "footwear"]),
            (.sportingGoods, ["dick's sporting", "sporting goods", "academy sports", "bicycle", "rei "]),
        ]
        for (category, keys) in buckets where keys.contains(where: { hay.contains($0) }) {
            return category
        }
        return nil
    }

    // MARK: Printed return window — "return within 30 days" and variants.

    private static func returnDays(in hay: String) -> Int? {
        let patterns = [
            #"return[^.\n]{0,24}?(\d{1,3})\s*day"#,   // "returns accepted within 30 days"
            #"(\d{1,3})[\s-]*day[^.\n]{0,16}?return"#, // "30-day return policy"
        ]
        for p in patterns {
            if let n = firstInt(p, in: hay), (1...365).contains(n) { return n }
        }
        return nil
    }

    // MARK: Printed warranty — "1 year warranty" / "12 month warranty".

    private static func warrantyMonths(in hay: String) -> Int? {
        // Years, either side of the word "warranty". `[\s-]*` allows the
        // hyphenated "2-year" form as well as "2 year".
        for p in [#"(\d{1,2})[\s-]*(?:year|yr)s?[^.\n]{0,16}?warrant"#,
                  #"warrant[^.\n]{0,16}?(\d{1,2})[\s-]*(?:year|yr)s?"#] {
            if let y = firstInt(p, in: hay), (1...10).contains(y) { return y * 12 }
        }
        // Months, either side.
        for p in [#"(\d{1,3})[\s-]*month[^.\n]{0,16}?warrant"#,
                  #"warrant[^.\n]{0,16}?(\d{1,3})[\s-]*month"#] {
            if let m = firstInt(p, in: hay), (1...120).contains(m) { return m }
        }
        return nil
    }

    /// Replace standalone spelled-out cardinals (one…twelve, and the common
    /// return-window tens) with their digits, so "one year warranty" and
    /// "thirty day returns" reach the numeric detectors. Word-boundaried to
    /// avoid touching substrings ("oneida", "twentieth").
    private static func spellOutToDigits(_ text: String) -> String {
        // Longest words first so "thirty" isn't half-consumed, etc.
        let words: [(String, String)] = [
            ("thirty", "30"), ("twenty", "20"), ("fifteen", "15"),
            ("fourteen", "14"), ("thirteen", "13"), ("twelve", "12"),
            ("eleven", "11"), ("ninety", "90"), ("sixty", "60"),
            ("ten", "10"), ("nine", "9"), ("eight", "8"), ("seven", "7"),
            ("six", "6"), ("five", "5"), ("four", "4"), ("three", "3"),
            ("two", "2"), ("one", "1"),
        ]
        var out = text
        for (word, digit) in words {
            out = out.replacingOccurrences(
                of: "\\b\(word)\\b", with: digit, options: .regularExpression)
        }
        return out
    }

    /// First capture group of `pattern`, as an Int, over the whole text.
    private static func firstInt(_ pattern: String, in text: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges > 1,
              let r = Range(match.range(at: 1), in: text) else { return nil }
        return Int(text[r])
    }
}
