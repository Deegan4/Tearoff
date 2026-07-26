import Foundation

/// How many camera scans a user may still take.
///
/// Camera + AI extraction is a Pro feature (spec §7), but a receipt scanner is
/// a "watch it work once" product — a hard gate asks people to buy a feature
/// they have never seen. This grants a small lifetime allowance so the paywall
/// lands *after* the moment that sells it rather than before.
///
/// The allowance is deliberately not a subscription trial: it is a fixed
/// lifetime count, so there is no renewal, expiry, or clock to reason about.
public struct ScanAllowance: Sendable, Equatable {
    /// Lifetime free scans. Enough to prove the extraction works on the user's
    /// own receipts (and to feed the accuracy ledger real non-payer data),
    /// while staying well short of a usable free tier.
    public static let freeLimit = 3

    public let isPro: Bool
    /// Lifetime count of scans that reached the confirm step. Clamped at zero
    /// so a corrupt stored value can never grant extra scans.
    public let freeScansUsed: Int

    public init(isPro: Bool, freeScansUsed: Int) {
        self.isPro = isPro
        self.freeScansUsed = max(0, freeScansUsed)
    }

    /// Scans left, or `nil` when unlimited. `nil` means "no number to show" —
    /// callers should not print a count for Pro users.
    public var remaining: Int? {
        isPro ? nil : max(0, Self.freeLimit - freeScansUsed)
    }

    /// Whether the camera may be opened at all.
    public var canScan: Bool {
        isPro || freeScansUsed < Self.freeLimit
    }

    /// The free allowance is spent and the user has not upgraded — the moment
    /// the paywall has actually earned the right to appear.
    public var isExhausted: Bool {
        !isPro && freeScansUsed >= Self.freeLimit
    }

    /// Whether to tell the user how many free scans are left. Suppressed for
    /// Pro (no limit) and before the first scan (nothing has been spent yet,
    /// so a counter would read as a restriction rather than a gift).
    public var shouldShowRemainingCount: Bool {
        !isPro && freeScansUsed > 0
    }
}
