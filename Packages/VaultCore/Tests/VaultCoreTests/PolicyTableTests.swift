import Foundation
import Testing
@testable import VaultCore

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.utcGregorian.date(from: DateComponents(year: y, month: m, day: d))!
}

@Test("Merchant keys normalize case, punctuation and whitespace")
func normalizationCollapsesVariants() {
    #expect(PolicyTable.normalize("Best Buy") == "bestbuy")
    #expect(PolicyTable.normalize("BEST BUY #1234") == "bestbuy1234")
    #expect(PolicyTable.normalize("  target  ") == "target")
    #expect(PolicyTable.normalize("Lowe's") == "lowes")
}

@Test("Returns the rule in effect on the purchase date, not the newest rule")
func selectsRuleEffectiveOnPurchaseDate() {
    let table = PolicyTable(rules: [
        PolicyRule(merchantKey: "target", category: nil, windowDays: 90, effectiveDate: date(2020, 1, 1)),
        PolicyRule(merchantKey: "target", category: nil, windowDays: 30, effectiveDate: date(2026, 1, 1))
    ])

    let old = table.rule(merchantKey: "target", category: .apparel, on: date(2025, 6, 1))
    #expect(old?.windowDays == 90, "a 2025 purchase must keep the policy that applied in 2025")

    let new = table.rule(merchantKey: "target", category: .apparel, on: date(2026, 6, 1))
    #expect(new?.windowDays == 30)
}

@Test("Category-specific rule beats a general rule with the same effective date")
func categorySpecificWins() {
    let table = PolicyTable(rules: [
        PolicyRule(merchantKey: "bestbuy", category: nil, windowDays: 60, effectiveDate: date(2020, 1, 1)),
        PolicyRule(merchantKey: "bestbuy", category: .electronics, windowDays: 15, effectiveDate: date(2020, 1, 1))
    ])

    #expect(table.rule(merchantKey: "bestbuy", category: .electronics, on: date(2026, 1, 1))?.windowDays == 15)
    #expect(table.rule(merchantKey: "bestbuy", category: .apparel, on: date(2026, 1, 1))?.windowDays == 60)
}

@Test("A purchase predating every rule returns nil rather than guessing")
func purchaseBeforeAnyRuleReturnsNil() {
    let table = PolicyTable(rules: [
        PolicyRule(merchantKey: "target", category: nil, windowDays: 90, effectiveDate: date(2020, 1, 1))
    ])
    #expect(table.rule(merchantKey: "target", category: .apparel, on: date(2019, 1, 1)) == nil)
}

@Test("Unknown merchant returns nil")
func unknownMerchantReturnsNil() {
    let table = PolicyTable(rules: [])
    #expect(table.rule(merchantKey: "nowhere", category: .tools, on: date(2026, 1, 1)) == nil)
}

@Test("Bundled policy table loads and covers the shipped retailer set")
func bundledTableLoads() throws {
    let table = try PolicyTable.bundled()
    // Tracks the shipped table deliberately: this failing means the curated
    // data shrank, which should never happen silently. Raise it as retailers
    // are verified and added.
    #expect(table.merchantCount >= 19, "P0a ships 19 curated returnable-goods retailers")
}

@Test("Bundled table resolves a known merchant")
func bundledTableResolvesKnownMerchant() throws {
    let table = try PolicyTable.bundled()
    let rule = table.rule(merchantKey: "costco", category: .electronics, on: date(2026, 6, 1))
    #expect(rule != nil, "Costco must be present in the shipped table")
}
