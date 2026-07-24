import Foundation
import Testing
@testable import VaultCore

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.utcGregorian.date(from: DateComponents(year: y, month: m, day: d))!
}

@Test("A field the parser left blank is never presented, so never scored")
func blankFieldNotPresented() {
    let parsed = ExtractionSnapshot(merchant: "Best Buy")   // no category
    let saved = ExtractionSnapshot(merchant: "Best Buy", category: .electronics)
    let r = ExtractionAudit.compare(parsed: parsed, saved: saved)
    #expect(r.presented == [.merchant])
    #expect(r.corrected.isEmpty)   // user *added* a category; not a miss
}

@Test("A presented field the user changed counts as corrected")
func changedFieldIsCorrected() {
    let parsed = ExtractionSnapshot(merchant: "Best Bvy", totalCents: Cents(4999))
    let saved = ExtractionSnapshot(merchant: "Best Buy", totalCents: Cents(4999))
    let r = ExtractionAudit.compare(parsed: parsed, saved: saved)
    #expect(r.presented == [.merchant, .total])
    #expect(r.corrected == [.merchant])
}

@Test("Same-day dates are not a correction even if the clock time differs")
func sameDayNotCorrected() {
    let parsed = ExtractionSnapshot(date: day(2026, 3, 4))
    let saved = ExtractionSnapshot(date: day(2026, 3, 4).addingTimeInterval(3600))
    let r = ExtractionAudit.compare(parsed: parsed, saved: saved)
    #expect(r.presented == [.date])
    #expect(r.corrected.isEmpty)
}

@Test("Whitespace-only differences in text fields are ignored")
func whitespaceIgnored() {
    let parsed = ExtractionSnapshot(merchant: "Home Depot ", orderNumber: " 4172-33471")
    let saved = ExtractionSnapshot(merchant: "Home Depot", orderNumber: "4172-33471")
    let r = ExtractionAudit.compare(parsed: parsed, saved: saved)
    #expect(r.corrected.isEmpty)
}

@Test("Ledger folds results into per-field accuracy")
func ledgerAccuracy() {
    var ledger = AccuracyLedger()
    // 3 scans present a merchant; 1 corrected.
    ledger.record(.init(presented: [.merchant], corrected: [.merchant]))
    ledger.record(.init(presented: [.merchant], corrected: []))
    ledger.record(.init(presented: [.merchant, .total], corrected: []))

    #expect(ledger.scanCount == 3)
    #expect(ledger.presented(.merchant) == 3)
    #expect(ledger.corrected(.merchant) == 1)
    #expect(ledger.accuracy(for: .merchant) == 2.0 / 3.0)
    #expect(ledger.accuracy(for: .total) == 1.0)          // presented once, never corrected
    #expect(ledger.accuracy(for: .category) == nil)       // never presented → no data
}

@Test("Overall accuracy is presentation-weighted across fields")
func overallAccuracy() {
    var ledger = AccuracyLedger()
    ledger.record(.init(presented: [.merchant, .total, .category], corrected: [.category]))
    // 3 presented, 1 corrected -> 2/3
    #expect(ledger.overallAccuracy == 2.0 / 3.0)
}

@Test("An empty ledger reports no accuracy rather than a false 100%")
func emptyLedgerHasNoAccuracy() {
    let ledger = AccuracyLedger()
    #expect(ledger.overallAccuracy == nil)
    #expect(ledger.accuracy(for: .merchant) == nil)
}

@Test("Ledger round-trips through Codable")
func ledgerCodable() throws {
    var ledger = AccuracyLedger()
    ledger.record(.init(presented: [.merchant, .warranty], corrected: [.warranty]))
    let data = try JSONEncoder().encode(ledger)
    let decoded = try JSONDecoder().decode(AccuracyLedger.self, from: data)
    #expect(decoded == ledger)
}
