import Foundation
import VaultCore

/// The fields we try to lift off a receipt. Everything is optional because
/// OCR is best-effort; the user confirms/corrects on the printed slip.
struct ParsedReceipt {
    var merchant: String
    var date: Date?
    var totalCents: Cents?
}

/// Heuristic receipt parser. Deliberately conservative: it never invents a
/// value it cannot find in the text. Duration/policy is still resolved by
/// VaultCore from the merchant + category, not guessed here.
enum ReceiptParser {
    static func parse(_ lines: [String]) -> ParsedReceipt {
        ParsedReceipt(
            merchant: merchant(from: lines),
            date: date(from: lines),
            totalCents: total(from: lines)
        )
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
        let trimmed = s.trimmingCharacters(in: .whitespaces)
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
}
