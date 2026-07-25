#if DEBUG
import Foundation
import SwiftData
import VaultCore

/// Debug-only sample data so the vault, widget, Live Activity, and insights
/// have something to show. Seeds once into an empty vault; never touches real
/// data and is compiled out of release builds.
enum MockData {
    private static let seededKey = "tearoff.didSeedMockData"

    @MainActor
    static func seedIfNeeded(_ context: ModelContext) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: seededKey) else { return }
        let existing = (try? context.fetchCount(FetchDescriptor<StoredPurchase>())) ?? 0
        guard existing == 0 else {
            defaults.set(true, forKey: seededKey)   // don't clobber a real vault
            return
        }
        for spec in specs { context.insert(spec.make()) }
        try? context.save()
        defaults.set(true, forKey: seededKey)
    }

    private static func daysAgo(_ n: Int) -> Date {
        Calendar.current.date(byAdding: .day, value: -n, to: Date()) ?? Date()
    }

    private struct Spec {
        var merchant: String
        var daysAgo: Int
        var cents: Int
        var category: PurchaseCategory
        var returnDays: Int?
        var warrantyMonths: Int?
        var status: PurchaseStatus = .active
        var payment: String = ""
        var order: String = ""
        var note: String = ""

        @MainActor
        func make() -> StoredPurchase {
            let p = StoredPurchase(
                merchant: merchant,
                purchaseDate: MockData.daysAgo(daysAgo),
                totalCents: Cents(cents),
                category: category,
                note: note)
            p.printedWindowDays = returnDays
            p.printedWarrantyMonths = warrantyMonths
            p.status = status
            p.paymentMethod = payment
            p.orderNumber = order
            return p
        }
    }

    private static let specs: [Spec] = [
        // Return closes ~tomorrow → drives the Live Activity + urgent widget.
        Spec(merchant: "Best Buy", daysAgo: 14, cents: 34999, category: .electronics,
             returnDays: 15, warrantyMonths: 12, payment: "Visa ••••4021",
             order: "BBY01-806357193", note: "Sony WH-1000XM5 headphones"),
        // Return closes in ~5 days → urgent-orange in the widget.
        Spec(merchant: "Old Navy", daysAgo: 40, cents: 4240, category: .apparel,
             returnDays: 45, payment: "Mastercard ••••7788", note: "Denim jeans"),
        Spec(merchant: "Apple Store", daysAgo: 3, cents: 1900, category: .electronics,
             returnDays: 14, warrantyMonths: 12, note: "USB-C charge cable"),
        Spec(merchant: "The Home Depot", daysAgo: 20, cents: 15900, category: .tools,
             returnDays: 90, warrantyMonths: 36, order: "4172-00091-33471",
             note: "DeWalt 20V drill kit"),
        Spec(merchant: "Target", daysAgo: 30, cents: 5999, category: .appliances,
             returnDays: 90, warrantyMonths: 12, note: "Coffee maker"),
        Spec(merchant: "IKEA", daysAgo: 60, cents: 6999, category: .furniture,
             returnDays: 365, note: "MALM bookcase"),
        // Not returnable — shows the consumable gate + appears in insights totals.
        Spec(merchant: "Costco", daysAgo: 5, cents: 8420, category: .groceries,
             returnDays: nil, payment: "Debit ••••1122", note: "Weekly groceries"),
        // Resolved records — realistic history, excluded from open-return value.
        Spec(merchant: "Nordstrom", daysAgo: 100, cents: 12900, category: .apparel,
             returnDays: 90, status: .kept, note: "Leather boots"),
        Spec(merchant: "Walmart", daysAgo: 25, cents: 3499, category: .appliances,
             returnDays: 90, status: .returned, note: "Blender — returned"),
    ]
}
#endif
