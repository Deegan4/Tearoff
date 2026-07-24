import Foundation
import Testing
@testable import VaultCore

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.utcGregorian.date(from: DateComponents(year: y, month: m, day: d))!
}

private let sample = ExportablePurchase(
    merchant: "Best Buy",
    purchaseDate: day(2026, 3, 1),
    category: "Electronics",
    totalCents: 40260,
    status: "Active",
    returnDeadline: day(2026, 3, 16),
    warrantyDeadline: day(2027, 3, 1),
    orderNumber: "BBY01-806357193",
    paymentMethod: "Visa ••••4021",
    note: "Headphones"
)

@Test("CSV has a header row then one row per purchase")
func csvShape() {
    let csv = VaultExport.csv([sample])
    let lines = csv.split(separator: "\r\n", omittingEmptySubsequences: true)
    #expect(lines.count == 2)
    #expect(lines[0].hasPrefix("Merchant,Purchase Date,Category,Total,Status"))
    #expect(lines[1].contains("Best Buy"))
    #expect(lines[1].contains("402.60"))
    #expect(lines[1].contains("2026-03-16"))   // return deadline, ISO date
}

@Test("Fields with commas, quotes, or newlines are RFC-4180 quoted")
func csvEscaping() {
    let tricky = ExportablePurchase(
        merchant: "Dewey, Cheatem & Howe",
        purchaseDate: day(2026, 1, 2),
        category: "Other",
        totalCents: 1999,
        status: "Active",
        note: "line one\nline \"two\""
    )
    let csv = VaultExport.csv([tricky])
    #expect(csv.contains("\"Dewey, Cheatem & Howe\""))       // comma → quoted
    #expect(csv.contains("\"line one\nline \"\"two\"\"\""))  // newline + doubled quotes
}

@Test("A missing deadline exports as an empty field, not the word nil")
func csvEmptyDeadline() {
    let noWindows = ExportablePurchase(
        merchant: "Corner Store", purchaseDate: day(2026, 5, 5),
        category: "Groceries", totalCents: 500, status: "Kept"
    )
    let csv = VaultExport.csv([noWindows])
    let row = csv.split(separator: "\r\n")[1]
    // Corner Store,2026-05-05...,Groceries,5.00,Kept,,,,,  -> two empty deadline fields
    #expect(!row.lowercased().contains("nil"))
    #expect(row.contains(",Kept,,,"))
}

@Test("Negative amounts (coupons) keep their sign")
func csvNegative() {
    let coupon = ExportablePurchase(
        merchant: "X", purchaseDate: day(2026, 1, 1),
        category: "Other", totalCents: -250, status: "Active"
    )
    #expect(VaultExport.csv([coupon]).contains("-2.50"))
}

@Test("JSON round-trips through Codable with ISO dates")
func jsonRoundTrip() throws {
    let data = try VaultExport.json([sample])
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode([ExportablePurchase].self, from: data)
    #expect(decoded == [sample])
}

@Test("An empty vault still produces a valid header-only CSV")
func csvEmptyVault() {
    let csv = VaultExport.csv([])
    #expect(csv == VaultExport.csvHeader.joined(separator: ",") + "\r\n")
}
