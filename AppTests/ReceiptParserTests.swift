import Testing
import Foundation
@testable import Tearoff
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

    @Test("Strips leading/trailing OCR symbols from the merchant", arguments: [
        ("> pharmacy", "pharmacy"),
        ("*WALGREENS*", "Walgreens"),
        ("  ::Target", "Target"),
    ])
    func merchantStripsEdgeSymbols(raw: String, expected: String) {
        let r = ReceiptParser.parse([raw, "TOTAL 5.00"])
        #expect(r.merchant == expected)
    }

    @Test("Keeps interior punctuation in the merchant name")
    func merchantKeepsInteriorPunctuation() {
        let r = ReceiptParser.parse(["H&M", "TOTAL 5.00"])
        #expect(r.merchant == "H&M")
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

    // MARK: Extra details

    @Test("Extracts subtotal and tax")
    func subtotalAndTax() {
        let r = ReceiptParser.parse(["SUBTOTAL 18.50", "TAX 1.49", "TOTAL 19.99"])
        #expect(r.subtotalCents?.raw == 1850)
        #expect(r.taxCents?.raw == 149)
    }

    @Test("Reads a masked card as payment method")
    func paymentMethodMaskedCard() {
        let r = ReceiptParser.parse(["VISA ****1234", "TOTAL 19.99"])
        #expect(r.paymentMethod == "Visa ••••1234")
    }

    @Test("Reads cash as payment method")
    func paymentMethodCash() {
        let r = ReceiptParser.parse(["CASH", "CHANGE 0.01", "TOTAL 19.99"])
        #expect(r.paymentMethod == "Cash")
    }

    @Test("Extracts an order/transaction number", arguments: [
        "Order #A1B2C3", "Transaction: 0092381", "Ref # 55012",
    ])
    func orderNumber(text: String) {
        let r = ReceiptParser.parse([text, "TOTAL 19.99"])
        #expect(r.orderNumber != nil)
    }

    @Test("Parses product line items, skipping totals")
    func lineItems() {
        let r = ReceiptParser.parse([
            "Coffee Beans 12.99",
            "Oat Milk 4.50",
            "SUBTOTAL 17.49",
            "TAX 1.40",
            "TOTAL 18.89",
        ])
        #expect(r.lineItems.count == 2)
        #expect(r.lineItems.first?.name == "Coffee Beans")
        #expect(r.lineItems.first?.cents == 1299)
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
