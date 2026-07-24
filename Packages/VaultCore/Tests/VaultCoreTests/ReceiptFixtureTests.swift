import Foundation
import Testing
@testable import VaultCore

// MARK: - Golden receipt corpus
//
// A regression corpus for `ReceiptParser`. Each fixture is the OCR text of a
// receipt (one entry per recognized line, top-to-bottom, exactly as Vision
// hands it to `ReceiptParser.parse`) plus the fields we expect the parser to
// lift off it.
//
// These are hand-authored to mirror the layout and noise of real thermal
// slips from the named retailers — they are the *seed* corpus. Real captures
// drop in as new `Fixture` entries with the same shape (paste the OCR lines,
// fill the expectations); nothing else has to change. The point is that any
// change to the parser's heuristics runs against every receipt shape we have
// ever cared about, so an "improvement" that regresses another format fails
// loudly here instead of in a user's vault.

/// Distinguishes "don't assert this field" (`.ignore`) from "assert it is
/// exactly this, including nil" (`.equals(nil)`). Without this, a fixture
/// could not pin down that, say, category is *deliberately* unknown.
private enum Expect<T: Equatable & Sendable>: Sendable {
    case ignore
    case equals(T?)

    func check(_ actual: T?, _ label: String, fixture: String, sourceLocation: SourceLocation = #_sourceLocation) {
        guard case let .equals(expected) = self else { return }
        #expect(actual == expected, "\(fixture): \(label) — expected \(String(describing: expected)), got \(String(describing: actual))", sourceLocation: sourceLocation)
    }
}

private struct Fixture: Sendable, CustomStringConvertible {
    let name: String
    let lines: [String]
    var merchant: Expect<String> = .ignore
    var totalCents: Expect<Cents> = .ignore
    var category: Expect<PurchaseCategory> = .ignore
    var printedReturnDays: Expect<Int> = .ignore
    var printedWarrantyMonths: Expect<Int> = .ignore
    var subtotalCents: Expect<Cents> = .ignore
    var taxCents: Expect<Cents> = .ignore
    var paymentMethod: Expect<String> = .ignore
    var orderNumber: Expect<String> = .ignore
    /// Names of line items the parser must have captured (subset check, so a
    /// fixture need not enumerate every product to pin the ones that matter).
    var mustContainItems: [String] = []
    /// Line-item names the parser must NOT have captured (e.g. a totals row).
    var mustNotContainItems: [String] = []

    var description: String { name }
}

private let corpus: [Fixture] = [
    Fixture(
        name: "Best Buy — electronics, printed return, card",
        lines: [
            "BEST BUY",
            "1717 Harrison St",
            "San Francisco CA 94103",
            "(415) 555-0142",
            "Sony WH-1000XM5 Headphones      349.99",
            "USB-C Cable 6ft                  19.99",
            "Subtotal                        369.98",
            "Sales Tax                        32.62",
            "TOTAL                           402.60",
            "VISA ************4021            402.60",
            "Return within 15 days with receipt",
            "Order #BBY01-806357193",
        ],
        merchant: .equals("Best Buy"),
        totalCents: .equals(Cents(40260)),
        category: .equals(.electronics),
        printedReturnDays: .equals(15),
        subtotalCents: .equals(Cents(36998)),
        taxCents: .equals(Cents(3262)),
        paymentMethod: .equals("Visa ••••4021"),
        orderNumber: .equals("BBY01-806357193"),
        mustContainItems: ["Sony WH-1000XM5 Headphones", "USB-C Cable 6ft"],
        mustNotContainItems: ["Subtotal", "Sales Tax", "TOTAL"]
    ),
    Fixture(
        name: "Home Depot — tools, 90-day return, warranty",
        lines: [
            "THE HOME DEPOT",
            "MORE SAVING. MORE DOING.",
            "DEWALT 20V Drill Kit            159.00",
            "Milwaukee Tape Measure 25ft      24.97",
            "SUBTOTAL                        183.97",
            "TAX                              16.19",
            "TOTAL                           200.16",
            "MASTERCARD ENDING IN 7788       200.16",
            "Return policy: 90 days",
            "3 year warranty on power tools",
            "TRANS #4172-00091-33471",
        ],
        merchant: .equals("The Home Depot"),
        totalCents: .equals(Cents(20016)),
        category: .equals(.tools),
        printedReturnDays: .equals(90),
        printedWarrantyMonths: .equals(36),
        paymentMethod: .equals("Mastercard ••••7788"),
        orderNumber: .equals("4172-00091-33471"),
        mustContainItems: ["DEWALT 20V Drill Kit", "Milwaukee Tape Measure 25ft"]
    ),
    Fixture(
        name: "Safeway — groceries, not returnable, cash",
        lines: [
            "SAFEWAY",
            "Store 1547",
            "Bananas 2.4 lb                    1.68",
            "Whole Milk Gallon                 3.99",
            "Sourdough Loaf                    4.49",
            "SUBTOTAL                         10.16",
            "TAX                               0.00",
            "TOTAL                            10.16",
            "CASH                             20.00",
            "CHANGE                            9.84",
        ],
        merchant: .equals("Safeway"),
        totalCents: .equals(Cents(1016)),
        category: .equals(.groceries),
        paymentMethod: .equals("Cash"),
        mustContainItems: ["Bananas", "Whole Milk Gallon", "Sourdough Loaf"],
        mustNotContainItems: ["CHANGE", "CASH", "TOTAL"]
    ),
    Fixture(
        name: "Shell — fuel, not returnable",
        lines: [
            "SHELL",
            "Pump 06",
            "Unleaded Regular",
            "12.014 GAL @ 4.199",
            "FUEL TOTAL                       50.44",
            "CREDIT                           50.44",
        ],
        merchant: .equals("Shell"),
        totalCents: .equals(Cents(5044)),
        category: .equals(.fuel)
    ),
    Fixture(
        name: "Olive Garden — restaurant, gratuity present",
        lines: [
            "OLIVE GARDEN",
            "Server: Marcus",
            "Chicken Alfredo                  17.99",
            "Minestrone Soup                   6.49",
            "Subtotal                         24.48",
            "Tax                               2.14",
            "TOTAL                            26.62",
            "Suggested Gratuity 18%            4.79",
        ],
        merchant: .equals("Olive Garden"),
        totalCents: .equals(Cents(2662)),
        category: .equals(.restaurant),
        subtotalCents: .equals(Cents(2448)),
        taxCents: .equals(Cents(214)),
        mustNotContainItems: ["Suggested Gratuity 18%", "Tax", "Subtotal"]
    ),
    Fixture(
        name: "CVS — pharmacy beats grocery keywords",
        lines: [
            "CVS pharmacy",
            "RX# 1938271",
            "Prescription Copay               10.00",
            "Vitamin D3 Softgels               8.49",
            "TOTAL                            18.49",
            "DEBIT ****1122                   18.49",
        ],
        merchant: .equals("CVS pharmacy"),
        totalCents: .equals(Cents(1849)),
        category: .equals(.pharmacy),
        paymentMethod: .equals("Debit ••••1122")
    ),
    Fixture(
        name: "Old Navy — apparel, 45-day return",
        lines: [
            "OLD NAVY",
            "Crew Tee Navy M                  12.00",
            "Denim Shorts                     26.99",
            "SUBTOTAL                         38.99",
            "TAX                               3.41",
            "TOTAL                            42.40",
            "Returns accepted within 45 days",
        ],
        merchant: .equals("Old Navy"),
        totalCents: .equals(Cents(4240)),
        category: .equals(.apparel),
        printedReturnDays: .equals(45),
        mustContainItems: ["Crew Tee Navy M", "Denim Shorts"]
    ),
    Fixture(
        name: "IKEA — furniture, 365-day return",
        lines: [
            "IKEA",
            "MALM Bed Frame Queen            279.00",
            "BILLY Bookcase White             69.99",
            "TOTAL                           348.99",
            "You may return items within 365 days",
        ],
        merchant: .equals("Ikea"),
        totalCents: .equals(Cents(34899)),
        category: .equals(.furniture),
        printedReturnDays: .equals(365)
    ),
    Fixture(
        name: "Local hardware — no keyword, category stays unknown",
        lines: [
            "Bob's Corner Store",
            "Assorted Sundries                 5.00",
            "TOTAL                             5.00",
        ],
        merchant: .equals("Bob's Corner Store"),
        totalCents: .equals(Cents(500)),
        category: .equals(nil)           // deliberately: no confident guess
    ),
    Fixture(
        name: "Apple Store — 1 year warranty, no printed return",
        lines: [
            "Apple Store",
            "Union Square",
            "USB-C Charge Cable               19.00",
            "TOTAL                            20.71",
            "One year limited warranty included",
        ],
        merchant: .equals("Apple Store"),
        category: .equals(.electronics),
        printedReturnDays: .equals(nil),  // no return term printed
        printedWarrantyMonths: .equals(12)
    ),
    Fixture(
        name: "Amex full brand name + order token",
        lines: [
            "Micro Center",
            "Graphics Card RTX                599.99",
            "TOTAL                           653.99",
            "AMERICAN EXPRESS ****3005        653.99",
            "Invoice: 220148-A",
        ],
        merchant: .equals("Micro Center"),
        category: .equals(.electronics),
        paymentMethod: .equals("Amex ••••3005"),
        orderNumber: .equals("220148-A")
    ),
    Fixture(
        name: "Noise-prefixed merchant line gets trimmed",
        lines: [
            ">> WHOLE FOODS MARKET <<",
            "Organic Kale                      3.49",
            "TOTAL                             3.49",
        ],
        merchant: .equals("Whole Foods Market"),
        category: .equals(.groceries)
    ),
]

@Test("Every golden receipt parses to its expected fields", arguments: corpus)
private func fixtureParses(_ f: Fixture) {
    let r = ReceiptParser.parse(f.lines)

    f.merchant.check(r.merchant, "merchant", fixture: f.name)
    f.totalCents.check(r.totalCents, "totalCents", fixture: f.name)
    f.category.check(r.category, "category", fixture: f.name)
    f.printedReturnDays.check(r.printedReturnDays, "printedReturnDays", fixture: f.name)
    f.printedWarrantyMonths.check(r.printedWarrantyMonths, "printedWarrantyMonths", fixture: f.name)
    f.subtotalCents.check(r.subtotalCents, "subtotalCents", fixture: f.name)
    f.taxCents.check(r.taxCents, "taxCents", fixture: f.name)
    f.paymentMethod.check(r.paymentMethod, "paymentMethod", fixture: f.name)
    f.orderNumber.check(r.orderNumber, "orderNumber", fixture: f.name)

    let names = r.lineItems.map(\.name)
    for wanted in f.mustContainItems {
        #expect(names.contains(where: { $0.localizedCaseInsensitiveContains(wanted) }),
                "\(f.name): expected a line item whose name contains \"\(wanted)\", got \(names)")
    }
    for forbidden in f.mustNotContainItems {
        #expect(!names.contains(where: { $0.localizedCaseInsensitiveContains(forbidden) }),
                "\(f.name): a totals/label row leaked into line items as \"\(forbidden)\": \(names)")
    }
}
