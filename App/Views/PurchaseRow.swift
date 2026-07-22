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

            if let window = returnWindow {
                let days = window.daysRemaining(asOf: .now)
                Text(days >= 0
                     ? "Return within \(days) day\(days == 1 ? "" : "s") — \(window.provenance.explanation)"
                     : "Return window closed — \(window.provenance.explanation)")
                    .font(.caption)
                    .foregroundStyle(days < 0 ? Color.secondary : (days <= 3 ? .red : .secondary))
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
