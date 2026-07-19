import Foundation

/// An amount of money in integer minor units (e.g. US cents).
///
/// Money is never stored as a floating-point value anywhere in iPrint.
/// Binary floating point cannot represent 0.10 exactly, and accumulated
/// error in a totals column is a correctness bug that surfaces as a
/// receipt that does not match the paper one.
public struct Cents: Hashable, Codable, Sendable, Comparable {
    public let raw: Int

    public init(_ raw: Int) {
        self.raw = raw
    }

    public static func + (lhs: Cents, rhs: Cents) -> Cents { Cents(lhs.raw + rhs.raw) }
    public static func - (lhs: Cents, rhs: Cents) -> Cents { Cents(lhs.raw - rhs.raw) }
    public static func * (lhs: Cents, rhs: Int) -> Cents { Cents(lhs.raw * rhs) }
    public static func < (lhs: Cents, rhs: Cents) -> Bool { lhs.raw < rhs.raw }

    public func formatted(currencyCode: String) -> String {
        let amount = Decimal(raw) / 100
        return amount.formatted(.currency(code: currencyCode).locale(Locale(identifier: "en_US")))
    }
}
