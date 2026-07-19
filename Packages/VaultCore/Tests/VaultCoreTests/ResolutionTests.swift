import Foundation
import Testing
@testable import VaultCore

private let utc = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "UTC")!
    return c
}()

private func date(_ y: Int, _ m: Int, _ d: Int) -> Date {
    utc.date(from: DateComponents(year: y, month: m, day: d))!
}

@Test("Deadline is purchase date plus window days")
func deadlineAddsDays() {
    let r = WindowResolution(
        purchaseDate: date(2026, 1, 1),
        days: 30,
        provenance: .printed,
        calendar: utc
    )
    #expect(r.deadline == date(2026, 1, 31))
}

@Test("Deadline crosses a leap-year February correctly")
func deadlineCrossesLeapFebruary() {
    let r = WindowResolution(
        purchaseDate: date(2028, 2, 1),
        days: 30,
        provenance: .table,
        calendar: utc
    )
    #expect(r.deadline == date(2028, 3, 2))
}

@Test("Printed provenance is not an estimate")
func printedIsNotEstimate() {
    #expect(!Provenance.printed.isEstimate)
    #expect(!Provenance.table.isEstimate)
    #expect(!Provenance.user.isEstimate)
}

@Test("Category default is an estimate and must be labelled as one")
func categoryDefaultIsEstimate() {
    #expect(Provenance.categoryDefault.isEstimate)
}

@Test("Every provenance has a user-facing explanation")
func allProvenancesExplain() {
    for p in Provenance.allCases {
        #expect(!p.explanation.isEmpty)
    }
}

@Test("daysRemaining is 0 when now is the deadline day, at any time")
func daysRemainingZeroOnDeadlineDay() {
    let r = WindowResolution(
        purchaseDate: date(2026, 2, 12),
        days: 30,
        provenance: .printed,
        calendar: utc
    )
    // deadline is 2026-03-14
    let midnight = date(2026, 3, 14)
    let evening = utc.date(byAdding: .hour, value: 18, to: midnight)!
    #expect(r.daysRemaining(asOf: midnight, calendar: utc) == 0)
    #expect(r.daysRemaining(asOf: evening, calendar: utc) == 0)
}

@Test("daysRemaining is 1 the day before the deadline, at any time")
func daysRemainingOneDayBefore() {
    let r = WindowResolution(
        purchaseDate: date(2026, 2, 12),
        days: 30,
        provenance: .printed,
        calendar: utc
    )
    // deadline is 2026-03-14
    let dayBeforeMidnight = date(2026, 3, 13)
    let dayBeforeEvening = utc.date(byAdding: .hour, value: 18, to: dayBeforeMidnight)!
    #expect(r.daysRemaining(asOf: dayBeforeMidnight, calendar: utc) == 1)
    #expect(r.daysRemaining(asOf: dayBeforeEvening, calendar: utc) == 1)
}

@Test("daysRemaining is -1 the day after the deadline, at any time")
func daysRemainingOneDayAfter() {
    let r = WindowResolution(
        purchaseDate: date(2026, 2, 12),
        days: 30,
        provenance: .printed,
        calendar: utc
    )
    // deadline is 2026-03-14
    let dayAfterMidnight = date(2026, 3, 15)
    let dayAfterMorning = utc.date(byAdding: .hour, value: 6, to: dayAfterMidnight)!
    #expect(r.daysRemaining(asOf: dayAfterMidnight, calendar: utc) == -1)
    #expect(r.daysRemaining(asOf: dayAfterMorning, calendar: utc) == -1)
}

@Test("daysRemaining does not depend on time-of-day of now")
func daysRemainingIndependentOfTimeOfDay() {
    let r = WindowResolution(
        purchaseDate: date(2026, 2, 12),
        days: 30,
        provenance: .printed,
        calendar: utc
    )
    // deadline is 2026-03-14; now = one day before, at 23:59
    let dayBefore = date(2026, 3, 13)
    let almostMidnight = utc.date(byAdding: DateComponents(hour: 23, minute: 59), to: dayBefore)!
    #expect(r.daysRemaining(asOf: almostMidnight, calendar: utc) == 1)
}
