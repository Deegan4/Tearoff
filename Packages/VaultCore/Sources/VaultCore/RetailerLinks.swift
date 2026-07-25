import Foundation

/// Deep links to retailers' returns pages, so "start my return" can jump
/// straight to the right place. A known merchant maps to its returns URL;
/// anything unknown falls back to a web search for that retailer's policy —
/// never a dead end.
public enum RetailerLinks {
    private static let table: [(needles: [String], url: String)] = [
        (["best buy", "bestbuy"], "https://www.bestbuy.com/returns"),
        (["home depot", "homedepot"], "https://www.homedepot.com/c/Returns_Policy"),
        (["target"], "https://www.target.com/returns"),
        (["walmart"], "https://www.walmart.com/cp/returns/1229937"),
        (["amazon"], "https://www.amazon.com/returns"),
        (["apple"], "https://www.apple.com/shop/help/returns_refund/return_policy"),
        (["costco"], "https://www.costco.com/returns.html"),
        (["ikea"], "https://www.ikea.com/us/en/customer-service/returns-claims/"),
        (["old navy", "oldnavy"], "https://oldnavy.gap.com/customerService/info.do?cid=81222"),
        (["lowe's", "lowes"], "https://www.lowes.com/l/help/returns-policy"),
        (["nordstrom"], "https://www.nordstrom.com/browse/customer-service/returns"),
        (["macy's", "macys"], "https://www.macys.com/help/returns"),
        (["cvs"], "https://www.cvs.com/help/help_subtopic_details.jsp?subtopicName=Returns"),
    ]

    /// A returns page for `merchant`, or a web search fallback. Never nil for a
    /// non-empty merchant.
    public static func returnsURL(forMerchant merchant: String) -> URL? {
        let m = merchant.lowercased()
        for row in table where row.needles.contains(where: { m.contains($0) }) {
            return URL(string: row.url)
        }
        let trimmed = merchant.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let query = "\(trimmed) return policy"
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "return+policy"
        return URL(string: "https://www.google.com/search?q=\(query)")
    }

    /// Whether `merchant` matched a known retailer (vs. the search fallback).
    public static func isKnown(_ merchant: String) -> Bool {
        let m = merchant.lowercased()
        return table.contains { $0.needles.contains(where: { m.contains($0) }) }
    }
}
