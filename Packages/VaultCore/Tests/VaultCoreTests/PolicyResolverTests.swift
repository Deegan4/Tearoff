import Foundation
import Testing
@testable import VaultCore

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.utcGregorian.date(from: DateComponents(year: y, month: m, day: d))!
}

private let table = PolicyTable(rules: [
    PolicyRule(merchantKey: "target", category: nil, windowDays: 90, effectiveDate: date(2020, 1, 1))
])

@Test("A printed window beats the curated table")
func printedBeatsTable() {
    let r = PolicyResolver(table: table).resolve(
        merchant: "Target",
        category: .apparel,
        purchaseDate: date(2026, 3, 1),
        printedWindowDays: 45,
        userWindowDays: nil
    )
    #expect(r?.provenance == .printed)
    #expect(r?.deadline == date(2026, 4, 15))
}

@Test("A user override beats everything, including a printed window")
func userBeatsPrinted() {
    let r = PolicyResolver(table: table).resolve(
        merchant: "Target",
        category: .apparel,
        purchaseDate: date(2026, 3, 1),
        printedWindowDays: 45,
        userWindowDays: 10
    )
    #expect(r?.provenance == .user)
    #expect(r?.deadline == date(2026, 3, 11))
}

@Test("Falls back to the curated table when nothing is printed")
func fallsBackToTable() {
    let r = PolicyResolver(table: table).resolve(
        merchant: "TARGET #0428",
        category: .apparel,
        purchaseDate: date(2026, 3, 1),
        printedWindowDays: nil,
        userWindowDays: nil
    )
    #expect(r?.provenance == .table)
    #expect(r?.deadline == date(2026, 5, 30))
}

@Test("Returns nil for an unknown merchant rather than guessing")
func resolverUnknownMerchantReturnsNil() {
    let r = PolicyResolver(table: table).resolve(
        merchant: "Joe's Corner Store",
        category: .tools,
        purchaseDate: date(2026, 3, 1),
        printedWindowDays: nil,
        userWindowDays: nil
    )
    #expect(r == nil)
}

@Test("Consumable categories never get a window, even at a known merchant")
func consumablesGetNoWindow() {
    let r = PolicyResolver(table: table).resolve(
        merchant: "Target",
        category: .groceries,
        purchaseDate: date(2026, 3, 1),
        printedWindowDays: 90,
        userWindowDays: nil
    )
    #expect(r == nil, "milk does not get a return countdown")
}

@Test("A zero or negative printed window is rejected as bad extraction")
func nonPositiveWindowRejected() {
    let resolver = PolicyResolver(table: table)
    let zero = resolver.resolve(
        merchant: "Joe's Corner Store", category: .tools,
        purchaseDate: date(2026, 3, 1), printedWindowDays: 0, userWindowDays: nil
    )
    #expect(zero == nil)
}
