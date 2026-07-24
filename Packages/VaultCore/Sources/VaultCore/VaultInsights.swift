import Foundation

/// A purchase reduced to just what insights need. Kept separate from
/// `ExportablePurchase` so the "is this still active?" semantics are explicit
/// rather than inferred from a display string.
public struct InsightsInput: Sendable {
    public let category: String
    public let totalCents: Int
    public let isActive: Bool
    public let returnDeadline: Date?
    public let warrantyDeadline: Date?

    public init(category: String, totalCents: Int, isActive: Bool,
                returnDeadline: Date?, warrantyDeadline: Date?) {
        self.category = category
        self.totalCents = totalCents
        self.isActive = isActive
        self.returnDeadline = returnDeadline
        self.warrantyDeadline = warrantyDeadline
    }
}

public struct CategoryTotal: Equatable, Sendable, Identifiable {
    public let category: String
    public let totalCents: Int
    public let count: Int
    public var id: String { category }
}

/// The computed dashboard numbers. All money in cents; counts are counts.
public struct InsightsSummary: Equatable, Sendable {
    public let totalTrackedCents: Int
    public let purchaseCount: Int
    /// Value + count of active purchases whose return window is still open.
    public let openReturnValueCents: Int
    public let openReturnCount: Int
    /// Active warranties, and how many of those expire within the soon window.
    public let activeWarrantyCount: Int
    public let warrantiesExpiringSoonCount: Int
    /// Spend by category, highest total first.
    public let topCategories: [CategoryTotal]
}

/// Pure, deterministic aggregation over the vault. No SwiftData, no clock of
/// its own — `now` is passed in so tests pin every boundary.
public enum VaultInsights {
    public static func summary(
        _ inputs: [InsightsInput],
        now: Date,
        soonWindowDays: Int = 30,
        topCategoryLimit: Int = 5,
        calendar: Calendar = .utcGregorian
    ) -> InsightsSummary {
        let today = calendar.startOfDay(for: now)
        let soonCutoff = calendar.date(byAdding: .day, value: soonWindowDays, to: today) ?? today

        var totalTracked = 0
        var openReturnValue = 0
        var openReturnCount = 0
        var activeWarranties = 0
        var expiringSoon = 0
        var byCategory: [String: (total: Int, count: Int)] = [:]

        for p in inputs {
            totalTracked += p.totalCents
            let entry = byCategory[p.category] ?? (0, 0)
            byCategory[p.category] = (entry.total + p.totalCents, entry.count + 1)

            if p.isActive, let d = p.returnDeadline, calendar.startOfDay(for: d) >= today {
                openReturnValue += p.totalCents
                openReturnCount += 1
            }
            if let w = p.warrantyDeadline, calendar.startOfDay(for: w) >= today {
                activeWarranties += 1
                if calendar.startOfDay(for: w) <= soonCutoff { expiringSoon += 1 }
            }
        }

        let top = byCategory
            .map { CategoryTotal(category: $0.key, totalCents: $0.value.total, count: $0.value.count) }
            // Highest spend first; ties broken by name for determinism.
            .sorted { $0.totalCents != $1.totalCents ? $0.totalCents > $1.totalCents : $0.category < $1.category }
            .prefix(topCategoryLimit)

        return InsightsSummary(
            totalTrackedCents: totalTracked,
            purchaseCount: inputs.count,
            openReturnValueCents: openReturnValue,
            openReturnCount: openReturnCount,
            activeWarrantyCount: activeWarranties,
            warrantiesExpiringSoonCount: expiringSoon,
            topCategories: Array(top))
    }
}
