import Foundation
import Testing
@testable import VaultCore

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.utcGregorian.date(from: DateComponents(year: y, month: m, day: d))!
}

private let resolver = WarrantyResolver(defaults: [.electronics: 12, .tools: 12, .appliances: 12])

@Test("A printed warranty term beats the category default")
func printedBeatsDefault() {
    let r = resolver.resolve(
        category: .electronics,
        purchaseDate: date(2026, 1, 1),
        printedMonths: 24,
        userMonths: nil
    )
    #expect(r?.provenance == .printed)
    #expect(r?.deadline == date(2028, 1, 1))
}

// Renamed from the brief's `userBeatsPrinted` to `warrantyUserBeatsPrinted`:
// PolicyResolverTests.swift already defines a top-level `userBeatsPrinted`
// func, and the test target compiles all test files together, so the two
// would collide. Display string kept verbatim.
@Test("A user override beats a printed term")
func warrantyUserBeatsPrinted() {
    let r = resolver.resolve(
        category: .electronics,
        purchaseDate: date(2026, 1, 1),
        printedMonths: 24,
        userMonths: 36
    )
    #expect(r?.provenance == .user)
    #expect(r?.deadline == date(2029, 1, 1))
}

@Test("Category default applies when nothing is printed, and is flagged an estimate")
func categoryDefaultIsFlagged() {
    let r = resolver.resolve(
        category: .tools,
        purchaseDate: date(2026, 1, 1),
        printedMonths: nil,
        userMonths: nil
    )
    #expect(r?.provenance == .categoryDefault)
    #expect(r?.provenance.isEstimate == true)
    #expect(r?.deadline == date(2027, 1, 1))
}

@Test("Categories with no default return nil rather than inventing a warranty")
func noDefaultReturnsNil() {
    let r = resolver.resolve(
        category: .apparel,
        purchaseDate: date(2026, 1, 1),
        printedMonths: nil,
        userMonths: nil
    )
    #expect(r == nil, "clothing has no meaningful manufacturer warranty")
}

@Test("Consumables never get a warranty")
func consumablesGetNoWarranty() {
    let r = resolver.resolve(
        category: .groceries,
        purchaseDate: date(2026, 1, 1),
        printedMonths: 12,
        userMonths: nil
    )
    #expect(r == nil)
}

@Test("Bundled warranty defaults load")
func bundledDefaultsLoad() throws {
    let r = try WarrantyResolver.bundled()
    let result = r.resolve(
        category: .electronics,
        purchaseDate: date(2026, 1, 1),
        printedMonths: nil,
        userMonths: nil
    )
    #expect(result?.provenance == .categoryDefault)
}
