import Foundation

/// A resolved deadline plus the evidence behind it.
public struct WindowResolution: Hashable, Codable, Sendable {
    public let deadline: Date
    public let provenance: Provenance

    public init(
        purchaseDate: Date,
        days: Int,
        provenance: Provenance,
        calendar: Calendar = .utcGregorian
    ) {
        // Gregorian day arithmetic does not fail in practice for any real
        // purchase date. The `?? purchaseDate` fallback exists only so a
        // release build cannot silently present garbage; a debug build
        // asserts loudly instead so the failure is never silent.
        if let computed = calendar.date(byAdding: .day, value: days, to: purchaseDate) {
            self.deadline = computed
        } else {
            assertionFailure(
                "WindowResolution: calendar.date(byAdding: .day, value: \(days), to: \(purchaseDate)) returned nil; falling back to purchaseDate"
            )
            self.deadline = purchaseDate
        }
        self.provenance = provenance
    }

    public func daysRemaining(asOf now: Date, calendar: Calendar = .utcGregorian) -> Int {
        let startOfNow = calendar.startOfDay(for: now)
        let startOfDeadline = calendar.startOfDay(for: deadline)
        guard let days = calendar.dateComponents([.day], from: startOfNow, to: startOfDeadline).day else {
            // Whole-day differencing between two startOfDay values in the
            // same Gregorian calendar does not fail in practice. This
            // fallback exists only so a release build cannot silently
            // present a garbage day count.
            assertionFailure(
                "WindowResolution.daysRemaining: dateComponents(.day) returned nil for startOfNow: \(startOfNow), startOfDeadline: \(startOfDeadline)"
            )
            return 0
        }
        return days
    }
}

public extension Calendar {
    /// All window arithmetic uses UTC so a user crossing time zones never
    /// sees a deadline shift by a day.
    static let utcGregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
}
