import SwiftUI
import VaultCore

struct PurchaseRow: View {
    let purchase: StoredPurchase
    let returnWindow: WindowResolution?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(purchase.merchant.isEmpty ? "Unknown merchant" : purchase.merchant)
                    .font(.headline)
                Spacer()
                Text(purchase.totalCents.formatted(currencyCode: "USD"))
                    .font(.subheadline.monospacedDigit())
            }

            if purchase.status.isResolved {
                // A resolved purchase is done with its window — show the
                // outcome, not a countdown, and never the urgency pulse.
                Label(purchase.status.label, systemImage: purchase.status.systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if let window = returnWindow {
                let days = window.daysRemaining(asOf: .now)
                let urgent = (0...3).contains(days)
                HStack(spacing: 5) {
                    if urgent {
                        // Pulses while the return window is about to close.
                        Image(systemName: "clock.badge.exclamationmark")
                            .font(.caption)
                            .foregroundStyle(.red)
                            .symbolEffect(.pulse, options: .repeating)
                    }
                    Text(days >= 0
                         ? "Return within \(days) day\(days == 1 ? "" : "s") — \(window.provenance.explanation)"
                         : "Return window closed — \(window.provenance.explanation)")
                        .font(.caption)
                        .foregroundStyle(days < 0 ? Color.secondary : (urgent ? .red : .secondary))
                }
            } else {
                Text(purchase.category.isReturnable
                     ? "No return window on file"
                     : purchase.category.displayName)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
