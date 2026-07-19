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
        self.deadline = calendar.date(byAdding: .day, value: days, to: purchaseDate) ?? purchaseDate
        self.provenance = provenance
    }

    public func daysRemaining(asOf now: Date, calendar: Calendar = .utcGregorian) -> Int {
        calendar.dateComponents([.day], from: now, to: deadline).day ?? 0
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
