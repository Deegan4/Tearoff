import Foundation
import Testing
@testable import VaultCore

// MARK: - Ladder integrity

@Test("The ladder starts at zero so a brand-new vault still has a rank")
func ladderStartsAtZero() {
    #expect(RankLadder.ranks.first?.xpThreshold == 0)
    #expect(RankLadder.progress(xp: 0).rank.level == 1)
}

@Test("Levels are 1-based, contiguous, and in order")
func levelsAreContiguous() {
    let levels = RankLadder.ranks.map(\.level)
    #expect(levels == Array(1...RankLadder.ranks.count))
}

@Test("Thresholds strictly increase, so every rank is reachable and distinct")
func thresholdsStrictlyIncrease() {
    let thresholds = RankLadder.ranks.map(\.xpThreshold)
    #expect(thresholds == thresholds.sorted())
    #expect(Set(thresholds).count == thresholds.count)
}

@Test("Every rank has copy and a symbol — an unnamed rung would render blank")
func everyRankIsPresentable() {
    for rank in RankLadder.ranks {
        #expect(!rank.title.isEmpty)
        #expect(!rank.blurb.isEmpty)
        #expect(!rank.symbolName.isEmpty)
    }
}

// MARK: - Scoring

@Test("An empty vault scores zero")
func emptyVaultScoresZero() {
    #expect(RankLadder.xp(purchasesTracked: 0, scansConfirmed: 0, returnsCompleted: 0) == 0)
}

@Test("A scan is a bonus on top of the purchase award, not a separate track")
func scanIsABonusNotAReplacement() {
    let typed = RankLadder.xp(purchasesTracked: 1, scansConfirmed: 0, returnsCompleted: 0)
    let scanned = RankLadder.xp(purchasesTracked: 1, scansConfirmed: 1, returnsCompleted: 0)
    #expect(typed == RankLadder.xpPerPurchase)
    #expect(scanned == RankLadder.xpPerPurchase + RankLadder.xpScanBonus)
    #expect(scanned > typed)
}

@Test("A completed return outweighs merely logging the purchase")
func returnsOutweighLogging() {
    #expect(RankLadder.xpPerCompletedReturn > RankLadder.xpPerPurchase + RankLadder.xpScanBonus)
}

@Test("Free-tier users can reach every rank without ever scanning")
func freeTierCanReachMaxRank() {
    // Camera scanning is Pro-gated. If the ladder were only climbable with
    // scans it would be a paywall wearing a joke, so prove the top rank is
    // reachable on manual entry + returns alone.
    let xp = RankLadder.xp(purchasesTracked: 300, scansConfirmed: 0, returnsCompleted: 30)
    #expect(xp >= RankLadder.maxRank.xpThreshold)
    #expect(RankLadder.progress(xp: xp).isMaxRank)
}

@Test("Negative tallies clamp to zero rather than producing negative XP")
func negativeTalliesClamp() {
    #expect(RankLadder.xp(purchasesTracked: -5, scansConfirmed: -5, returnsCompleted: -5) == 0)
    let p = RankLadder.progress(xp: -100)
    #expect(p.xp == 0)
    #expect(p.rank.level == 1)
}

// MARK: - Placement

@Test("Landing exactly on a threshold promotes, rather than falling one short")
func exactThresholdPromotes() {
    for rank in RankLadder.ranks {
        #expect(RankLadder.progress(xp: rank.xpThreshold).rank.level == rank.level)
    }
}

@Test("One XP below a threshold is still the previous rank")
func oneBelowThresholdDoesNotPromote() {
    for rank in RankLadder.ranks.dropFirst() {
        let p = RankLadder.progress(xp: rank.xpThreshold - 1)
        #expect(p.rank.level == rank.level - 1)
        #expect(p.next?.level == rank.level)
    }
}

@Test("XP beyond the ladder pins to the top rank instead of running off the end")
func beyondLadderPinsToMax() {
    let p = RankLadder.progress(xp: RankLadder.maxRank.xpThreshold * 10)
    #expect(p.rank == RankLadder.maxRank)
    #expect(p.next == nil)
    #expect(p.isMaxRank)
    #expect(p.xpToNext == nil)
}

// MARK: - Progress arithmetic

@Test("A full progress bar at max rank reads as complete, not empty")
func maxRankBarIsFull() {
    // Guards a classic off-by-one: with no next rank the span is nil, and a
    // naive divide would yield 0 — showing the best rank with an empty bar.
    #expect(RankLadder.progress(xp: RankLadder.maxRank.xpThreshold).fractionToNext == 1)
}

@Test("Progress through a level is proportional")
func progressIsProportional() {
    let first = RankLadder.ranks[0]
    let second = RankLadder.ranks[1]
    let midpoint = first.xpThreshold + (second.xpThreshold - first.xpThreshold) / 2
    let p = RankLadder.progress(xp: midpoint)
    #expect(abs(p.fractionToNext - 0.5) < 0.01)
    #expect(p.xpIntoLevel == midpoint - first.xpThreshold)
}

@Test("fractionToNext never escapes 0...1 anywhere on the ladder")
func fractionStaysInBounds() {
    for xp in stride(from: 0, through: RankLadder.maxRank.xpThreshold + 500, by: 7) {
        let f = RankLadder.progress(xp: xp).fractionToNext
        #expect(f >= 0 && f <= 1)
    }
}

@Test("xpToNext counts down to exactly zero at the next threshold")
func xpToNextCountsDown() {
    let second = RankLadder.ranks[1]
    #expect(RankLadder.progress(xp: 0).xpToNext == second.xpThreshold)
    #expect(RankLadder.progress(xp: second.xpThreshold - 10).xpToNext == 10)
    #expect(RankLadder.progress(xp: second.xpThreshold).rank.level == 2)
}

@Test("Rank never decreases as XP increases")
func rankIsMonotonic() {
    var lastLevel = 0
    for xp in stride(from: 0, through: RankLadder.maxRank.xpThreshold + 100, by: 13) {
        let level = RankLadder.progress(xp: xp).rank.level
        #expect(level >= lastLevel)
        lastLevel = level
    }
}

@Test("The convenience overload agrees with scoring then placing")
func convenienceOverloadMatches() {
    let a = RankLadder.progress(purchasesTracked: 12, scansConfirmed: 5, returnsCompleted: 2)
    let b = RankLadder.progress(xp: RankLadder.xp(
        purchasesTracked: 12, scansConfirmed: 5, returnsCompleted: 2))
    #expect(a == b)
}
