import SwiftUI
import VaultCore

/// A clean, static proof-of-purchase card rendered to an image for sharing —
/// something you can show at the returns desk or attach to a warranty claim.
/// Always light (white paper, dark ink) so it reads the same wherever it lands.
struct ProofCard: View {
    let purchase: StoredPurchase
    var returnWindow: WindowResolution?
    var warranty: WindowResolution?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("TEAROFF")
                    .font(.system(.subheadline, design: .monospaced).weight(.bold))
                    .tracking(4)
                Spacer()
                Text("PROOF OF PURCHASE")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.black.opacity(0.5))
            }

            Rectangle().fill(.black.opacity(0.15)).frame(height: 1)

            VStack(spacing: 8) {
                row("Merchant", purchase.merchant)
                row("Date", purchase.purchaseDate.formatted(date: .abbreviated, time: .omitted))
                row("Total", purchase.totalCents.formatted(currencyCode: "USD"))
                row("Category", purchase.category.displayName)
                if !purchase.barcode.isEmpty {
                    row("Barcode", purchase.barcode)
                }
                if let returnWindow {
                    row("Return by", returnWindow.deadline.formatted(date: .abbreviated, time: .omitted))
                }
                if let warranty {
                    row("Warranty until", warranty.deadline.formatted(date: .abbreviated, time: .omitted))
                }
                if !purchase.paymentMethod.isEmpty {
                    row("Payment", purchase.paymentMethod)
                }
                if !purchase.orderNumber.isEmpty {
                    row("Order #", purchase.orderNumber)
                }
                row("Status", purchase.status.label)
            }
        }
        .padding(22)
        .frame(width: 360, alignment: .leading)
        .background(.white)
        .foregroundStyle(.black)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(.subheadline, design: .monospaced))
                .foregroundStyle(.black.opacity(0.5))
            Spacer(minLength: 12)
            Text(value)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}
