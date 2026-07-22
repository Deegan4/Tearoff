import SwiftUI
import VaultCore

/// Animated "thermal printer" presentation of a purchase. The paper feeds
/// out of a slot at the top: the printed area is revealed top-to-bottom
/// (as a real printer emits paper), the leading edge is a clean cut until
/// the slip is fully out, then a torn perforated edge appears and the
/// hanging paper settles with a short wobble.
struct ReceiptPrintView: View {
    let purchase: StoredPurchase
    var onDone: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var paperHeight: CGFloat = 0
    @State private var progress: CGFloat = 0      // 0 = tucked in slot, 1 = fully printed
    @State private var sway: Double = 0           // degrees, for the settle wobble
    @State private var done = false
    @State private var feedBlink = false

    private let paperWidth: CGFloat = 268

    private var returnWindow: WindowResolution? {
        ResolverStore.shared.returnWindow(for: purchase)
    }
    private var warrantyWindow: WindowResolution? {
        ResolverStore.shared.warrantyWindow(for: purchase)
    }

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            VStack(spacing: 0) {
                printer
                    .zIndex(1)

                receiptPaper
                    .rotationEffect(.degrees(sway), anchor: .top)
                    // Reveal the printed height from the top down: the header
                    // stays pinned under the slot while paper feeds out below.
                    .frame(height: max(paperHeight * progress, 0), alignment: .top)
                    .clipped()
                    // The leading edge — a roller/print-head shadow — travels
                    // down with the paper, so it reads as being fed out.
                    .overlay(alignment: .bottom) {
                        if !done && progress > 0.01 {
                            leadingEdge
                        }
                    }
                    .padding(.top, -7)   // tuck the top under the slot lip

                Spacer(minLength: 0)
            }
            .padding(.top, 24)

            VStack {
                Spacer()
                Button(action: onDone) {
                    Text(done ? "Done" : "Printing…")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(PressableButtonStyle())
                .background(.tint, in: .rect(cornerRadius: 14))
                .foregroundStyle(.white)
                .disabled(!done)
                .opacity(done ? 1 : 0.5)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        .onAppear(perform: startPrinting)
    }

    // MARK: - Printer housing & feed edge

    private var printer: some View {
        ZStack {
            // Housing body.
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.34), Color(white: 0.16)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: paperWidth + 60, height: 54)
                .shadow(color: .black.opacity(0.3), radius: 6, y: 3)
            // A soft power light, blinking while feeding.
            Circle()
                .fill(done ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .opacity(feedBlink ? 1 : 0.3)
                .offset(x: (paperWidth + 60) / 2 - 16, y: -14)
            // The exit slot — a recessed dark mouth the paper comes out of.
            RoundedRectangle(cornerRadius: 3)
                .fill(
                    LinearGradient(
                        colors: [.black, Color(white: 0.1)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: paperWidth + 20, height: 10)
                .overlay(
                    Capsule().fill(Color.black.opacity(0.9)).frame(height: 4)
                )
                .offset(y: 16)
        }
    }

    /// Roller shadow at the paper's leading edge, sold with a thin dark line
    /// and a gradient, so the emerging edge looks like it is bending off a
    /// print roller.
    private var leadingEdge: some View {
        ZStack(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.14)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 16)
            Rectangle()
                .fill(Color.black.opacity(0.35))
                .frame(height: 1.5)
        }
    }

    // MARK: - Paper

    private var receiptPaper: some View {
        receiptContent
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .frame(width: paperWidth, alignment: .top)
            .background(
                ReceiptSlip(toothWidth: 12, toothHeight: 7, torn: done)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 4)
            )
            // Capture the natural paper height once, to drive the reveal.
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { if paperHeight == 0 { paperHeight = geo.size.height } }
                }
            )
    }

    private var receiptContent: some View {
        VStack(spacing: 8) {
            Text("iPRINT")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .tracking(6)
            dashed

            line("MERCHANT", purchase.merchant.isEmpty ? "—" : purchase.merchant)
            line("DATE", purchase.purchaseDate.formatted(date: .abbreviated, time: .omitted))
            line("CATEGORY", purchase.category.displayName)
            dashed
            line("TOTAL", purchase.totalCents.formatted(currencyCode: "USD"), emphasized: true)

            if let w = returnWindow {
                dashed
                stacked("RETURN BY",
                        w.deadline.formatted(date: .abbreviated, time: .omitted),
                        w.provenance.explanation,
                        estimate: w.provenance.isEstimate)
            }
            if let w = warrantyWindow {
                dashed
                stacked("WARRANTY UNTIL",
                        w.deadline.formatted(date: .abbreviated, time: .omitted),
                        w.provenance.explanation,
                        estimate: w.provenance.isEstimate)
            }

            solid
            Barcode(seed: purchase.id)
                .frame(height: 42)
                .padding(.top, 2)
            Text("THANK YOU")
                .font(.system(.caption2, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Row builders

    private func line(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(emphasized ? .body : .caption, design: .monospaced)
                    .weight(emphasized ? .bold : .regular))
                .multilineTextAlignment(.trailing)
        }
    }

    private func stacked(_ label: String, _ value: String, _ note: String, estimate: Bool) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.body, design: .monospaced).weight(.semibold))
            Text(estimate ? "\(note) *" : note)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(estimate ? .orange : .secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var dashed: some View {
        Text(String(repeating: "-", count: 30))
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    private var solid: some View {
        Text(String(repeating: "=", count: 30))
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
    }

    // MARK: - Animation driver

    private func startPrinting() {
        guard progress == 0 else { return }
        if reduceMotion {
            progress = 1
            done = true
            return
        }
        // Blink the feed light while paper advances.
        withAnimation(.easeInOut(duration: 0.35).repeatForever(autoreverses: true)) {
            feedBlink = true
        }
        // Linear feed reads as a steady mechanical advance, not a wipe.
        withAnimation(.linear(duration: 2.1)) {
            progress = 1
        } completion: {
            feedBlink = false
            withAnimation(.easeInOut(duration: 0.2)) { done = true }   // tear-off edge appears
            sway = 5
            withAnimation(.interpolatingSpring(stiffness: 130, damping: 6)) {
                sway = 0
            }
        }
    }
}

/// Receipt paper outline. The bottom is a straight cut while printing and a
/// torn perforated (zigzag) edge once the slip is fully out.
private struct ReceiptSlip: Shape {
    var toothWidth: CGFloat = 12
    var toothHeight: CGFloat = 7
    var torn: Bool

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))

        guard torn else {
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            p.closeSubpath()
            return p
        }

        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - toothHeight))
        var x = rect.maxX
        var up = false
        while x > rect.minX {
            let nextX = max(x - toothWidth, rect.minX)
            let y = up ? rect.maxY - toothHeight : rect.maxY
            p.addLine(to: CGPoint(x: nextX, y: y))
            x = nextX
            up.toggle()
        }
        p.closeSubpath()
        return p
    }
}

/// A decorative barcode. Deterministic per purchase id so a given receipt
/// always renders the same bars.
private struct Barcode: View {
    let seed: UUID

    var body: some View {
        Canvas { context, size in
            let bytes = Array(seed.uuidString.utf8)
            var x: CGFloat = 0
            var i = 0
            while x < size.width && i < 200 {
                let w = CGFloat(1 + Int(bytes[i % bytes.count]) % 4)
                if i % 2 == 0 {
                    let bar = Path(CGRect(x: x, y: 0, width: w, height: size.height))
                    context.fill(bar, with: .color(.black))
                }
                x += w
                i += 1
            }
        }
    }
}

/// pressto-style press feedback: the control scales down while held.
private struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}
