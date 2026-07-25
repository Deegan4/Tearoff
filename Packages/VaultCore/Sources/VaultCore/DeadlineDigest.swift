import Foundation

/// Which kind of deadline a widget row represents.
public enum DeadlineKind: String, Codable, Sendable {
    case returnWindow
    case warranty

    public var label: String {
        switch self {
        case .returnWindow: "Return"
        case .warranty: "Warranty"
        }
    }
}

/// A single upcoming deadline, flattened for the Home Screen widget. Codable so
/// the app can publish a digest to a shared App Group container that the widget
/// extension reads — the widget never touches SwiftData directly.
public struct UpcomingDeadline: Codable, Equatable, Sendable, Identifiable {
    /// Stable identity: purchase id + kind, so the same row updates in place.
    public var id: String
    public var merchant: String
    public var kind: DeadlineKind
    public var deadline: Date
    /// True when the deadline came from a category estimate, not a hard source.
    public var isEstimate: Bool

    public init(id: String, merchant: String, kind: DeadlineKind, deadline: Date, isEstimate: Bool) {
        self.id = id
        self.merchant = merchant
        self.kind = kind
        self.deadline = deadline
        self.isEstimate = isEstimate
    }

    /// Canonical row identity: the purchase's UUID and the deadline kind, joined
    /// by a separator that can't occur inside a UUID string so `purchaseID` can
    /// recover the purchase later (e.g. from a widget "Mark returned" tap).
    public static func makeID(purchaseID: UUID, kind: DeadlineKind) -> String {
        "\(purchaseID.uuidString)|\(kind.rawValue)"
    }

    /// The originating purchase's UUID string, parsed back out of `id`, or nil
    /// if the id doesn't follow the `makeID` convention.
    public var purchaseID: String? {
        guard let raw = id.split(separator: "|", maxSplits: 1).first,
              UUID(uuidString: String(raw)) != nil else { return nil }
        return String(raw)
    }
}

/// The published snapshot the widget renders. Carries a generation timestamp so
/// the widget can show how fresh it is.
public struct DeadlineDigest: Codable, Equatable, Sendable {
    public var generatedAt: Date
    public var deadlines: [UpcomingDeadline]
    /// True when the publishing user is on the free tier. Widgets are a Pro
    /// feature (spec §7); a locked digest carries no deadline data at all, so
    /// the widget extension shows an upsell instead of real content.
    public var isLocked: Bool

    public init(generatedAt: Date, deadlines: [UpcomingDeadline], isLocked: Bool = false) {
        self.generatedAt = generatedAt
        self.deadlines = deadlines
        self.isLocked = isLocked
    }

    /// Filename/key used for the shared container payload.
    public static let storageKey = "deadline-digest.json"

    /// Build a digest: keep only deadlines that have not yet passed (day-based,
    /// so a deadline *today* still shows), soonest first, capped at `limit`.
    public static func build(
        from items: [UpcomingDeadline],
        now: Date,
        limit: Int = 8,
        calendar: Calendar = .utcGregorian
    ) -> DeadlineDigest {
        let today = calendar.startOfDay(for: now)
        let upcoming = items
            .filter { calendar.startOfDay(for: $0.deadline) >= today }
            .sorted { $0.deadline < $1.deadline }
            .prefix(limit)
        return DeadlineDigest(generatedAt: now, deadlines: Array(upcoming))
    }

    /// The digest published for a free-tier user: no deadline data, flagged
    /// as locked so the widget renders an upsell rather than an empty state.
    public static func locked(now: Date) -> DeadlineDigest {
        DeadlineDigest(generatedAt: now, deadlines: [], isLocked: true)
    }

    /// Whole days from `now` to `deadline` (day-normalized). Negative if past.
    public static func daysRemaining(to deadline: Date, from now: Date, calendar: Calendar = .utcGregorian) -> Int {
        let a = calendar.startOfDay(for: now)
        let b = calendar.startOfDay(for: deadline)
        return calendar.dateComponents([.day], from: a, to: b).day ?? 0
    }
}
