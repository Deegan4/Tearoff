import Testing
import Foundation
@testable import iPrint
import VaultCore

/// Tests for the heuristic receipt parser. The parser is deliberately
/// conservative — it returns `nil`/defaults rather than guessing — so these
/// tests pin both the confident-hit and the no-hit behaviour.
struct ReceiptParserTests {

    // MARK: Merchant

    @Test("Picks the first name-like line as the merchant")
    func merchantFromNameLine() {
        let r = ReceiptParser.parse(["123 Main St", "BEST BUY", "TOTAL 10.00"])
        // ALL-CAPS is tidied to title case.
        #expect(r.merchant == "Best Buy")
    }

    // MARK: Total

    @Test("Prefers a labelled TOTAL over larger unrelated amounts")
    func totalPrefersLabel() {
        let r = ReceiptParser.parse([
            "SUBTOTAL 99.99",
            "TAX 8.00",
            "TOTAL 12.99",
        ])
        #expect(r.totalCents?.raw == 1299)
    }

    @Test("Falls back to the largest amount when nothing is labelled TOTAL")
    func totalFallsBackToLargest() {
        let r = ReceiptParser.parse(["Item A 4.50", "Item B 21.00"])
        #expect(r.totalCents?.raw == 2100)
    }

    // MARK: Date

    @Test("Parses a numeric MM/dd/yyyy date")
    func parsesNumericDate() throws {
        let r = ReceiptParser.parse(["Store", "03/14/2024", "TOTAL 5.00"])
        let date = try #require(r.date)
        let comps = Calendar(identifier: .gregorian)
            .dateComponents([.year, .month, .day], from: date)
        #expect(comps.year == 2024 && comps.month == 3 && comps.day == 14)
    }

    // MARK: Category inference

    @Test("Merchant keywords map to a category", arguments: [
        ("WALGREENS #1234\nPrescription\nTOTAL 12.00", PurchaseCategory.pharmacy),
        ("SHELL\n9.812 GALLONS UNLEADED\nTOTAL 41.00", .fuel),
        ("BEST BUY\nLAPTOP\nTOTAL 999.00", .electronics),
        ("THE HOME DEPOT\nHARDWARE\nTOTAL 30.00", .tools),
        ("SAFEWAY SUPERMARKET\nTOTAL 60.00", .groceries),
    ])
    func categoryFromKeywords(text: String, expected: PurchaseCategory) {
        let r = ReceiptParser.parse(text.components(separatedBy: "\n"))
        #expect(r.category == expected)
    }

    @Test("No category keyword leaves category unset")
    func categoryUnknownWhenAmbiguous() {
        let r = ReceiptParser.parse(["Corner Store", "Widget 3.00", "TOTAL 3.00"])
        #expect(r.category == nil)
    }

    // MARK: Printed return window

    @Test("Reads a printed return window", arguments: [
        ("Returns accepted within 30 days", 30),
        ("90-day return policy", 90),
        ("Return within 14 days of purchase", 14),
    ])
    func readsReturnDays(text: String, expected: Int) {
        let r = ReceiptParser.parse(["Store", text, "TOTAL 5.00"])
        #expect(r.printedReturnDays == expected)
    }

    @Test("No return phrase leaves the return window unset")
    func returnDaysUnsetWhenAbsent() {
        let r = ReceiptParser.parse(["Store", "Thank you", "TOTAL 5.00"])
        #expect(r.printedReturnDays == nil)
    }

    // MARK: Printed warranty

    @Test("Reads a printed warranty term as months", arguments: [
        ("1 year warranty included", 12),
        ("2-year limited warranty", 24),
        ("12 month warranty", 12),
        ("Warranty: 3 years", 36),
    ])
    func readsWarrantyMonths(text: String, expected: Int) {
        let r = ReceiptParser.parse(["Store", text, "TOTAL 5.00"])
        #expect(r.printedWarrantyMonths == expected)
    }

    @Test("Out-of-range warranty is rejected as OCR noise")
    func warrantyRejectsNoise() {
        // 99 years exceeds the 1...10 year bound and must not be accepted.
        let r = ReceiptParser.parse(["Store", "99 year warranty", "TOTAL 5.00"])
        #expect(r.printedWarrantyMonths == nil)
    }

    // MARK: Empty input

    @Test("Empty input yields no inferred fields")
    func emptyInput() {
        let r = ReceiptParser.parse([])
        #expect(r.date == nil)
        #expect(r.totalCents == nil)
        #expect(r.category == nil)
        #expect(r.printedReturnDays == nil)
        #expect(r.printedWarrantyMonths == nil)
    }
}
