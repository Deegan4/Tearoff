import Foundation

/// A purchase flattened for export: only the fields a user (or their records)
/// would want out of the vault, already resolved to concrete deadlines. Kept
/// separate from the persistence model so export is a pure transform the App
/// feeds, and so it can be unit-tested without SwiftData.
public struct ExportablePurchase: Codable, Equatable, Sendable {
    public var merchant: String
    public var purchaseDate: Date
    public var category: String
    public var totalCents: Int
    public var status: String
    public var returnDeadline: Date?
    public var warrantyDeadline: Date?
    public var orderNumber: String
    public var paymentMethod: String
    public var note: String

    public init(
        merchant: String,
        purchaseDate: Date,
        category: String,
        totalCents: Int,
        status: String,
        returnDeadline: Date? = nil,
        warrantyDeadline: Date? = nil,
        orderNumber: String = "",
        paymentMethod: String = "",
        note: String = ""
    ) {
        self.merchant = merchant
        self.purchaseDate = purchaseDate
        self.category = category
        self.totalCents = totalCents
        self.status = status
        self.returnDeadline = returnDeadline
        self.warrantyDeadline = warrantyDeadline
        self.orderNumber = orderNumber
        self.paymentMethod = paymentMethod
        self.note = note
    }
}

/// Serializes the vault to portable formats. Pure and deterministic: dates are
/// ISO-8601 (UTC), amounts are plain dollars-and-cents strings, and CSV fields
/// are RFC-4180 quoted so a merchant with a comma or a note with a newline
/// can't corrupt the file.
public enum VaultExport {
    /// Column order for the CSV. Public so tests (and a docs table) can assert it.
    public static let csvHeader = [
        "Merchant", "Purchase Date", "Category", "Total", "Status",
        "Return Deadline", "Warranty Deadline", "Order Number",
        "Payment Method", "Note",
    ]

    public static func csv(_ purchases: [ExportablePurchase]) -> String {
        var rows = [csvHeader.map(escape).joined(separator: ",")]
        for p in purchases {
            let fields = [
                p.merchant,
                iso(p.purchaseDate),
                p.category,
                dollars(p.totalCents),
                p.status,
                p.returnDeadline.map(iso) ?? "",
                p.warrantyDeadline.map(iso) ?? "",
                p.orderNumber,
                p.paymentMethod,
                p.note,
            ]
            rows.append(fields.map(escape).joined(separator: ","))
        }
        // Trailing newline so the file ends cleanly and appends are line-safe.
        return rows.joined(separator: "\r\n") + "\r\n"
    }

    public static func json(_ purchases: [ExportablePurchase]) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(purchases)
    }

    // MARK: - Field formatting

    /// RFC-4180: wrap in quotes when the field contains a comma, quote, CR, or
    /// LF, and double any interior quotes.
    private static func escape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func dollars(_ cents: Int) -> String {
        let sign = cents < 0 ? "-" : ""
        let abs = Swift.abs(cents)
        return "\(sign)\(abs / 100).\(String(format: "%02d", abs % 100))"
    }

    /// ISO-8601 internet date-time in UTC (the `ISO8601FormatStyle` default),
    /// so no shared mutable formatter is needed under strict concurrency.
    private static func iso(_ date: Date) -> String { date.ISO8601Format() }
}
