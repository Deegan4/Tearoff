import Foundation

/// A field the scanner tries to lift off a receipt and the user can correct
/// on the confirm step. The unit of accuracy measurement.
public enum ExtractionField: String, CaseIterable, Codable, Sendable {
    case merchant, date, total, category, returnWindow, warranty, paymentMethod, orderNumber

    public var displayName: String {
        switch self {
        case .merchant: "Merchant"
        case .date: "Date"
        case .total: "Total"
        case .category: "Category"
        case .returnWindow: "Return window"
        case .warranty: "Warranty"
        case .paymentMethod: "Payment method"
        case .orderNumber: "Order number"
        }
    }
}

/// The editable fields as a flat, comparable snapshot. Built once from what
/// the parser produced and once from what the user saved, then diffed. Keeping
/// it separate from `ParsedReceipt` means the confirm screen's save path only
/// has to describe values, not thread parser internals through the UI.
public struct ExtractionSnapshot: Equatable, Sendable {
    public var merchant: String?
    public var date: Date?
    public var totalCents: Cents?
    public var category: PurchaseCategory?
    public var returnDays: Int?
    public var warrantyMonths: Int?
    public var paymentMethod: String?
    public var orderNumber: String?

    public init(
        merchant: String? = nil,
        date: Date? = nil,
        totalCents: Cents? = nil,
        category: PurchaseCategory? = nil,
        returnDays: Int? = nil,
        warrantyMonths: Int? = nil,
        paymentMethod: String? = nil,
        orderNumber: String? = nil
    ) {
        self.merchant = merchant
        self.date = date
        self.totalCents = totalCents
        self.category = category
        self.returnDays = returnDays
        self.warrantyMonths = warrantyMonths
        self.paymentMethod = paymentMethod
        self.orderNumber = orderNumber
    }
}

/// Pure diff of what the scanner presented versus what the user kept.
///
/// A field is *presented* only when the parser produced a usable value —
/// accuracy is meaningless for a field the scanner left blank, so those never
/// count against it (nor for it). A presented field is *corrected* when the
/// saved value differs from the presented one. Everything here is
/// side-effect-free so it can be unit-tested exhaustively.
public enum ExtractionAudit {
    public struct Result: Equatable, Sendable {
        public var presented: Set<ExtractionField>
        public var corrected: Set<ExtractionField>
        public init(presented: Set<ExtractionField>, corrected: Set<ExtractionField>) {
            self.presented = presented
            self.corrected = corrected
        }
    }

    public static func compare(
        parsed: ExtractionSnapshot,
        saved: ExtractionSnapshot,
        calendar: Calendar = .utcGregorian
    ) -> Result {
        var presented: Set<ExtractionField> = []
        var corrected: Set<ExtractionField> = []

        func note(_ field: ExtractionField, present: Bool, changed: Bool) {
            guard present else { return }
            presented.insert(field)
            if changed { corrected.insert(field) }
        }

        let pm = trimmed(parsed.merchant)
        note(.merchant, present: !pm.isEmpty, changed: pm != trimmed(saved.merchant))

        note(.date,
             present: parsed.date != nil,
             changed: !sameDay(parsed.date, saved.date, calendar))

        note(.total, present: parsed.totalCents != nil, changed: parsed.totalCents != saved.totalCents)
        note(.category, present: parsed.category != nil, changed: parsed.category != saved.category)
        note(.returnWindow, present: parsed.returnDays != nil, changed: parsed.returnDays != saved.returnDays)
        note(.warranty, present: parsed.warrantyMonths != nil, changed: parsed.warrantyMonths != saved.warrantyMonths)

        let pp = trimmed(parsed.paymentMethod)
        note(.paymentMethod, present: !pp.isEmpty, changed: pp != trimmed(saved.paymentMethod))

        let po = trimmed(parsed.orderNumber)
        note(.orderNumber, present: !po.isEmpty, changed: po != trimmed(saved.orderNumber))

        return Result(presented: presented, corrected: corrected)
    }

    private static func trimmed(_ s: String?) -> String {
        (s ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sameDay(_ a: Date?, _ b: Date?, _ calendar: Calendar) -> Bool {
        switch (a, b) {
        case (nil, nil): return true
        case let (x?, y?): return calendar.isDate(x, inSameDayAs: y)
        default: return false
        }
    }
}

/// Append-only, on-device aggregate of scan accuracy. Holds only counts —
/// never receipt contents — so it is safe to persist and show in Settings.
/// Codable so the App layer can serialize it wherever it likes.
public struct AccuracyLedger: Codable, Equatable, Sendable {
    /// How many scans were confirmed in total (denominator for "scans").
    public private(set) var scanCount: Int
    /// Per-field: how many times presented, and how many of those corrected.
    public private(set) var presentedCounts: [ExtractionField: Int]
    public private(set) var correctedCounts: [ExtractionField: Int]

    public init() {
        scanCount = 0
        presentedCounts = [:]
        correctedCounts = [:]
    }

    /// Fold one confirmed scan into the aggregate.
    public mutating func record(_ result: ExtractionAudit.Result) {
        scanCount += 1
        for field in result.presented {
            presentedCounts[field, default: 0] += 1
        }
        for field in result.corrected {
            correctedCounts[field, default: 0] += 1
        }
    }

    /// Fraction of presentations left unchanged, in `0...1`. `nil` when the
    /// field has never been presented (no data — distinct from "perfect").
    public func accuracy(for field: ExtractionField) -> Double? {
        guard let presented = presentedCounts[field], presented > 0 else { return nil }
        let corrected = correctedCounts[field] ?? 0
        return Double(presented - corrected) / Double(presented)
    }

    public func presented(_ field: ExtractionField) -> Int { presentedCounts[field] ?? 0 }
    public func corrected(_ field: ExtractionField) -> Int { correctedCounts[field] ?? 0 }

    /// Overall accuracy across every presented field, weighted by
    /// presentation count. `nil` until at least one field has been presented.
    public var overallAccuracy: Double? {
        let presented = presentedCounts.values.reduce(0, +)
        guard presented > 0 else { return nil }
        let corrected = correctedCounts.values.reduce(0, +)
        return Double(presented - corrected) / Double(presented)
    }
}
