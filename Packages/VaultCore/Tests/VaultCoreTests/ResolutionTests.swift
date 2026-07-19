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
