import Foundation
import Testing
@testable import VaultCore

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.utcGregorian.date(from: DateComponents(year: y, month: m, day: d))!
}

private let now = day(2026, 6, 1)

private let vault: [InsightsInput] = [
    // Active, return open (in 10 days), warranty in 20 days (soon)
    .init(category: "Electronics", totalCents: 40000, isActive: true,
          returnDeadline: day(2026, 6, 11), warrantyDeadline: day(2026, 6, 21)),
    // Active, return already passed → not counted as open
    .init(category: "Electronics", totalCents: 10000, isActive: true,
          returnDeadline: day(2026, 5, 20), warrantyDeadline: day(2027, 1, 1)),
    // Resolved (returned) → excluded from open-return value even if date open
    .init(category: "Apparel", totalCents: 5000, isActive: false,
          returnDeadline: day(2026, 6, 15), warrantyDeadline: nil),
    // Groceries, no windows
    .init(category: "Groceries", totalCents: 2000, isActive: true,
          returnDeadline: nil, warrantyDeadline: nil),
]

@Test("Totals and counts cover the whole vault")
func totals() {
    let s = VaultInsights.summary(vault, now: now)
    #expect(s.purchaseCount == 4)
    #expect(s.totalTrackedCents == 57000)
}

@Test("Open-return value counts only active, not-yet-passed windows")
func openReturns() {
    let s = VaultInsights.summary(vault, now: now)
    #expect(s.openReturnCount == 1)              // only the $400 electronics
    #expect(s.openReturnValueCents == 40000)
}

@Test("Warranty counts respect the soon window")
func warranties() {
    let s = VaultInsights.summary(vault, now: now, soonWindowDays: 30)
    #expect(s.activeWarrantyCount == 2)          // 6/21 and 2027-01-01
    #expect(s.warrantiesExpiringSoonCount == 1)  // only 6/21 within 30 days
}

@Test("Category totals rank by spend, highest first")
func categories() {
    let s = VaultInsights.summary(vault, now: now)
    #expect(s.topCategories.first?.category == "Electronics")
    #expect(s.topCategories.first?.totalCents == 50000)
    #expect(s.topCategories.first?.count == 2)
    #expect(s.topCategories.map(\.category) == ["Electronics", "Apparel", "Groceries"])
}

@Test("An empty vault yields zeros, not a crash")
func empty() {
    let s = VaultInsights.summary([], now: now)
    #expect(s.purchaseCount == 0)
    #expect(s.totalTrackedCents == 0)
    #expect(s.topCategories.isEmpty)
}
