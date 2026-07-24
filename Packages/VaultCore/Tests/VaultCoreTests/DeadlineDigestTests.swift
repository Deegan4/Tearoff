import Foundation
import Testing
@testable import VaultCore

private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
    Calendar.utcGregorian.date(from: DateComponents(year: y, month: m, day: d))!
}

private func deadline(_ id: String, _ date: Date, kind: DeadlineKind = .returnWindow, estimate: Bool = false) -> UpcomingDeadline {
    UpcomingDeadline(id: id, merchant: id, kind: kind, deadline: date, isEstimate: estimate)
}

@Test("Digest drops passed deadlines but keeps today's")
func dropsPast() {
    let now = day(2026, 6, 15)
    let items = [
        deadline("past", day(2026, 6, 14)),
        deadline("today", day(2026, 6, 15)),
        deadline("future", day(2026, 7, 1)),
    ]
    let digest = DeadlineDigest.build(from: items, now: now)
    #expect(digest.deadlines.map(\.id) == ["today", "future"])
}

@Test("Digest sorts soonest first and caps at the limit")
func sortsAndCaps() {
    let now = day(2026, 1, 1)
    let items = (1...10).map { deadline("d\($0)", day(2026, 1, 1 + $0)) }.shuffledStably()
    let digest = DeadlineDigest.build(from: items, now: now, limit: 3)
    #expect(digest.deadlines.count == 3)
    #expect(digest.deadlines.map(\.id) == ["d1", "d2", "d3"])
}

@Test("daysRemaining is day-normalized and signed")
func daysRemaining() {
    let now = day(2026, 3, 1)
    #expect(DeadlineDigest.daysRemaining(to: day(2026, 3, 4), from: now) == 3)
    #expect(DeadlineDigest.daysRemaining(to: day(2026, 3, 1), from: now) == 0)
    #expect(DeadlineDigest.daysRemaining(to: day(2026, 2, 27), from: now) == -2)
}

@Test("Digest round-trips through Codable")
func codable() throws {
    let digest = DeadlineDigest(generatedAt: day(2026, 1, 1), deadlines: [
        deadline("a", day(2026, 1, 5), kind: .warranty, estimate: true),
    ])
    let data = try JSONEncoder().encode(digest)
    let decoded = try JSONDecoder().decode(DeadlineDigest.self, from: data)
    #expect(decoded == digest)
}

// Deterministic shuffle so the sort test isn't trivially pre-ordered, without
// needing Date/Random (unavailable in this test env's constraints anyway).
private extension Array {
    func shuffledStably() -> [Element] {
        // Reverse + interleave halves — enough disorder to prove the sort runs.
        let mid = count / 2
        return Array(self[mid...].reversed()) + Array(self[..<mid])
    }
}
