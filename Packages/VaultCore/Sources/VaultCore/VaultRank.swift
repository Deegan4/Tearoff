import Foundation

/// One rung on the vault-keeper ladder.
///
/// Ranks are cosmetic — they never gate a feature, change a deadline, or
/// affect what the resolver computes. They exist so sustained use of the app
/// reads as progress rather than as an ever-growing list of chores.
public struct VaultRank: Sendable, Equatable, Identifiable {
    /// 1-based position on the ladder. Stable — persisted by the app layer to
    /// detect level-ups, so **never renumber an existing rank.**
    public let level: Int
    public let title: String
    /// The joke. Deadpan, in the house voice.
    public let blurb: String
    /// SF Symbol name. Resolved by the app layer; VaultCore never imports UI.
    public let symbolName: String
    /// Cumulative XP needed to reach this rank.
    public let xpThreshold: Int

    public var id: Int { level }

    public init(level: Int, title: String, blurb: String, symbolName: String, xpThreshold: Int) {
        self.level = level
        self.title = title
        self.blurb = blurb
        self.symbolName = symbolName
        self.xpThreshold = xpThreshold
    }
}

/// Where a given XP total sits on the ladder: the rank held, the one ahead,
/// and how far along the gap between them.
public struct RankProgress: Sendable, Equatable {
    public let xp: Int
    public let rank: VaultRank
    /// The next rank, or `nil` at the top of the ladder.
    public let next: VaultRank?

    public init(xp: Int, rank: VaultRank, next: VaultRank?) {
        self.xp = xp
        self.rank = rank
        self.next = next
    }

    public var isMaxRank: Bool { next == nil }

    /// XP earned since reaching the current rank.
    public var xpIntoLevel: Int { xp - rank.xpThreshold }

    /// Total XP between the current rank and the next. `nil` at max rank.
    public var xpSpanOfLevel: Int? {
        guard let next else { return nil }
        return next.xpThreshold - rank.xpThreshold
    }

    /// XP still needed for the next rank. `nil` at max rank.
    public var xpToNext: Int? {
        guard let next else { return nil }
        return max(0, next.xpThreshold - xp)
    }

    /// Progress toward the next rank, `0...1`. Always `1` at max rank so a
    /// progress bar reads as complete rather than empty.
    public var fractionToNext: Double {
        guard let span = xpSpanOfLevel, span > 0 else { return 1 }
        return min(1, max(0, Double(xpIntoLevel) / Double(span)))
    }
}

/// The ladder itself, plus the XP arithmetic.
///
/// Deliberately a pure lookup over counts: the app layer supplies the tallies
/// and gets a rank back. Nothing here persists, so the ladder can be retuned
/// in one place without a migration.
public enum RankLadder {
    // MARK: XP weights

    /// Every tracked purchase counts, however it was entered. Camera scanning
    /// is Pro-gated, so scoring scans *only* would make the ladder unreachable
    /// on the free tier — a joke nobody can participate in is just an advert.
    public static let xpPerPurchase = 10

    /// Bonus on top of `xpPerPurchase` when the purchase came from a confirmed
    /// scan. Rewards the Pro path without being the sole route up.
    public static let xpScanBonus = 15

    /// A purchase returned or refunded inside its window — the outcome the
    /// whole app exists to produce, and so the biggest single award.
    public static let xpPerCompletedReturn = 50

    // MARK: The ladder

    /// Append-only in spirit: retuning `xpThreshold` is fine, but changing a
    /// `level` number would silently re-badge existing users.
    public static let ranks: [VaultRank] = [
        VaultRank(level: 1, title: "Drawer Gremlin",
                  blurb: "Your receipts live in a drawer. The drawer is winning.",
                  symbolName: "archivebox.fill", xpThreshold: 0),
        VaultRank(level: 2, title: "Shoebox Apprentice",
                  blurb: "You have a system. The system is a shoebox.",
                  symbolName: "shippingbox.fill", xpThreshold: 50),
        VaultRank(level: 3, title: "Junior Filing Clerk",
                  blurb: "You have been trusted with a stapler.",
                  symbolName: "paperclip", xpThreshold: 150),
        VaultRank(level: 4, title: "Receipt Wrangler",
                  blurb: "Receipts fear you. Mildly.",
                  symbolName: "doc.text.fill", xpThreshold: 300),
        VaultRank(level: 5, title: "Deputy of Deadlines",
                  blurb: "You know when the window closes. You tell people. They did not ask.",
                  symbolName: "calendar.badge.clock", xpThreshold: 550),
        VaultRank(level: 6, title: "Warranty Whisperer",
                  blurb: "You have read a warranty. Voluntarily. All of it.",
                  symbolName: "shield.lefthalf.filled", xpThreshold: 900),
        VaultRank(level: 7, title: "Marshal of the Return Window",
                  blurb: "No window closes on your watch. Several have tried.",
                  symbolName: "checkmark.seal.fill", xpThreshold: 1400),
        VaultRank(level: 8, title: "Regional Manager of Regret",
                  blurb: "You have never once said \"ah well, I'll just keep it.\"",
                  symbolName: "crown.fill", xpThreshold: 2100),
        VaultRank(level: 9, title: "Keeper of the Vault",
                  blurb: "Retail associates recognize you. They are not pleased.",
                  symbolName: "building.columns.fill", xpThreshold: 3000),
        VaultRank(level: 10, title: "Grand Custodian of Crumpled Paper",
                  blurb: "There is no higher honor. There is also no lower bar.",
                  symbolName: "trophy.fill", xpThreshold: 4200),
    ]

    public static var maxRank: VaultRank {
        // The ladder is a non-empty compile-time literal; `last` cannot be nil.
        // Fall back to the first rung rather than crash if that ever changes.
        ranks.last ?? ranks[0]
    }

    // MARK: Scoring

    /// Total XP for a set of lifetime tallies.
    ///
    /// - Parameters:
    ///   - purchasesTracked: every purchase ever logged, scanned or typed.
    ///   - scansConfirmed: how many of those came from a confirmed scan. Adds
    ///     `xpScanBonus` *on top of* the per-purchase award, so it is a bonus
    ///     and not a separate track.
    ///   - returnsCompleted: purchases resolved as returned or refunded.
    ///
    /// Negative inputs are clamped to zero — a caller feeding a bad tally gets
    /// a low rank, never a negative one.
    public static func xp(
        purchasesTracked: Int,
        scansConfirmed: Int,
        returnsCompleted: Int
    ) -> Int {
        let purchases = max(0, purchasesTracked)
        let scans = max(0, scansConfirmed)
        let returns = max(0, returnsCompleted)
        return purchases * xpPerPurchase
            + scans * xpScanBonus
            + returns * xpPerCompletedReturn
    }

    /// The ladder position for an XP total. Clamps below zero to rank 1.
    public static func progress(xp: Int) -> RankProgress {
        let clamped = max(0, xp)
        // Highest rank whose threshold has been met. `ranks` is ordered by
        // threshold, so the last match wins.
        let current = ranks.last { clamped >= $0.xpThreshold } ?? ranks[0]
        let next = ranks.first { $0.xpThreshold > clamped }
        return RankProgress(xp: clamped, rank: current, next: next)
    }

    /// Convenience: score and place in one step.
    public static func progress(
        purchasesTracked: Int,
        scansConfirmed: Int,
        returnsCompleted: Int
    ) -> RankProgress {
        progress(xp: xp(
            purchasesTracked: purchasesTracked,
            scansConfirmed: scansConfirmed,
            returnsCompleted: returnsCompleted
        ))
    }
}
