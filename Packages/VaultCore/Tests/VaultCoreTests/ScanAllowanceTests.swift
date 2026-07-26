import Foundation
import Testing
@testable import VaultCore

@Test("A new free user gets the full allowance")
func freshFreeUserHasFullAllowance() {
    let a = ScanAllowance(isPro: false, freeScansUsed: 0)
    #expect(a.canScan)
    #expect(a.remaining == ScanAllowance.freeLimit)
    #expect(!a.isExhausted)
}

@Test("The allowance counts down scan by scan")
func allowanceCountsDown() {
    for used in 0..<ScanAllowance.freeLimit {
        let a = ScanAllowance(isPro: false, freeScansUsed: used)
        #expect(a.canScan)
        #expect(a.remaining == ScanAllowance.freeLimit - used)
    }
}

@Test("The last free scan is allowed, and the next one is not")
func lastScanAllowedThenExhausted() {
    // Guards the classic off-by-one: spending scan 3 of 3 must still work.
    let last = ScanAllowance(isPro: false, freeScansUsed: ScanAllowance.freeLimit - 1)
    #expect(last.canScan)
    #expect(last.remaining == 1)

    let spent = ScanAllowance(isPro: false, freeScansUsed: ScanAllowance.freeLimit)
    #expect(!spent.canScan)
    #expect(spent.remaining == 0)
    #expect(spent.isExhausted)
}

@Test("Pro scans without limit, whatever the stored free count says")
func proIsUnlimited() {
    for used in [0, 3, 999] {
        let a = ScanAllowance(isPro: true, freeScansUsed: used)
        #expect(a.canScan)
        #expect(a.remaining == nil)
        #expect(!a.isExhausted)
    }
}

@Test("Upgrading to Pro restores scanning after the free allowance is spent")
func upgradingRestoresScanning() {
    let spent = ScanAllowance(isPro: false, freeScansUsed: 10)
    #expect(!spent.canScan)
    let upgraded = ScanAllowance(isPro: true, freeScansUsed: 10)
    #expect(upgraded.canScan)
}

@Test("A negative or corrupt stored count cannot grant extra scans")
func negativeUsedCannotGrantExtraScans() {
    let a = ScanAllowance(isPro: false, freeScansUsed: -5)
    #expect(a.freeScansUsed == 0)
    #expect(a.remaining == ScanAllowance.freeLimit)
}

@Test("Overshooting the limit stays exhausted rather than going negative")
func overshootStaysClamped() {
    let a = ScanAllowance(isPro: false, freeScansUsed: ScanAllowance.freeLimit + 50)
    #expect(a.remaining == 0)
    #expect(!a.canScan)
    #expect(a.isExhausted)
}

@Test("The remaining-count hint is hidden before the first scan and for Pro")
func remainingHintVisibility() {
    // Showing "3 free scans left" before anyone has scanned reads as a
    // restriction; showing it after the first scan reads as what's left.
    #expect(!ScanAllowance(isPro: false, freeScansUsed: 0).shouldShowRemainingCount)
    #expect(ScanAllowance(isPro: false, freeScansUsed: 1).shouldShowRemainingCount)
    #expect(!ScanAllowance(isPro: true, freeScansUsed: 1).shouldShowRemainingCount)
}

@Test("The free limit is a small taste, not a usable free tier")
func freeLimitStaysSmall() {
    #expect(ScanAllowance.freeLimit > 0)
    #expect(ScanAllowance.freeLimit <= 5)
}
