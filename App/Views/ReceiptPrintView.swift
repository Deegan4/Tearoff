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

    // Resolved once at init rather than on every body pass — the resolver does
    // real work, and `rows` (which reads these) rebuilds throughout the feed
    // animation.
    private let returnWindow: WindowResolution?
    private let warrantyWindow: WindowResolution?

    init(purchase: StoredPurchase, onDone: @escaping () -> Void = {}) {
        self.purchase = purchase
        self.onDone = onDone
        self.returnWindow = ResolverStore.shared.returnWindow(for: purchase)
        self.warrantyWindow = ResolverStore.shared.warrantyWindow(for: purchase)
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss

    @State private var paperHeight: CGFloat = 0
    @State private var progress: CGFloat = 0      // 0 = tucked in slot, 1 = fully printed
    @State private var sway: Double = 0           // degrees, gravity pendulum on the hanging paper
    @State private var jitter: CGFloat = 0        // px, mechanical feed stepping
    @State private var done = false
    @State private var feedBlink = false

    private let paperWidth: CGFloat = 268

    var body: some View {
        ZStack {
            Color(.systemGroupedBackground).ignoresSafeArea()

            // Hidden copy at natural size, purely to measure the paper height
            // that drives the slide.
            measuringCopy

            VStack(spacing: 0) {
                // The whole hanging strip pivots at the slot, so it swings
                // under gravity like paper dangling from a printer.
                VStack(spacing: 0) {
                    printer
                        .zIndex(1)
                        .accessibilityHidden(true)

                    // Fixed window at the slot; the fully-printed strip slides
                    // straight down through it, from tucked-behind (offset up)
                    // to fully ejected. This is real downward motion, not a
                    // reveal — the sheet physically comes out of the printer.
                    ZStack(alignment: .top) {
                        if paperHeight > 0 {
                            receiptPaper
                                .offset(y: -paperHeight * (1 - progress) + jitter)
                        }
                    }
                    .frame(width: paperWidth, height: paperHeight, alignment: .top)
                    .clipped()
                    // Curling leading edge on the part hanging out of the slot.
                    .overlay(alignment: .bottom) {
                        if !done && progress > 0.01 && progress < 0.99 {
                            curlEdge
                        }
                    }
                    .shadow(color: .black.opacity(0.16), radius: 10, x: 0, y: 8)
                    .padding(.top, -6)   // tuck the window top behind the slot lip
                }
                .rotationEffect(.degrees(sway), anchor: .top)

                Spacer(minLength: 0)
            }
            .padding(.top, 24)

            VStack {
                Spacer()
                Button {
                    // Dismiss our own cover directly — reliable regardless of
                    // how the presenter is nested — then let the presenter do
                    // any extra teardown (e.g. close the form back to the vault).
                    NSLog("🧾TEAROFF Done tapped — done=\(done); calling dismiss()+onDone()")
                    dismiss()
                    onDone()
                    NSLog("🧾TEAROFF Done action finished")
                } label: {
                    Text(done ? "Done" : "Printing…")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                // iOS 26 Liquid Glass: a see-through, tinted glass button that
                // refracts the paper behind it instead of a flat blue fill.
                .buttonStyle(.glass)
                .tint(.blue)
                .disabled(!done)
                .opacity(done ? 1 : 0.5)
                .padding(.horizontal, 32)
                .padding(.bottom, 24)
            }
        }
        // Start the feed only once the paper has been measured. Kicking it off
        // from onAppear races the background height measurement: on slower
        // real-device layout the paper is inserted after the animation has
        // already run, so it appears fully printed with no motion. Gating on
        // paperHeight guarantees the strip is present before it feeds out.
        .onAppear { if paperHeight > 0 { startPrinting() } }
        .onChange(of: paperHeight) { _, height in
            if height > 0 { startPrinting() }
        }
    }

    // MARK: - Printer housing & feed edge

    private var printer: some View {
        let bodyWidth = paperWidth + 72
        return ZStack {
            // Rounded printer body with a raised top cover.
            VStack(spacing: 0) {
                // Top cover — a slightly lighter lid.
                RoundedRectangle(cornerRadius: 14)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.40), Color(white: 0.24)],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    .frame(width: bodyWidth - 16, height: 20)
                    .offset(y: 6)
                // Front face.
                UnevenRoundedRectangle(
                    cornerRadii: .init(topLeading: 6, bottomLeading: 16, bottomTrailing: 16, topTrailing: 6)
                )
                .fill(
                    LinearGradient(
                        colors: [Color(white: 0.30), Color(white: 0.15)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: bodyWidth, height: 46)
            }
            .shadow(color: .black.opacity(0.35), radius: 8, y: 4)

            // Controls on the front face: power light + two buttons.
            HStack(spacing: 10) {
                Circle()
                    .fill(done ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                    .opacity(feedBlink ? 1 : 0.3)
                    .shadow(color: (done ? Color.green : Color.orange).opacity(0.8), radius: feedBlink ? 4 : 0)
                Capsule().fill(Color(white: 0.5)).frame(width: 16, height: 5)
                Capsule().fill(Color(white: 0.5)).frame(width: 16, height: 5)
            }
            .offset(x: -bodyWidth / 2 + 34, y: 6)

            // The exit slot — a recessed dark mouth at the bottom lip that the
            // paper emerges from.
            RoundedRectangle(cornerRadius: 2)
                .fill(
                    LinearGradient(
                        colors: [.black, Color(white: 0.12)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: paperWidth + 18, height: 8)
                .overlay(Capsule().fill(Color.black).frame(height: 3))
                .offset(y: 25)
        }
    }

    /// Curling leading edge: the emerging paper tip catches light on top and
    /// drops a shadow below, so it reads as a physical curl coming off the
    /// printer rather than a flat wipe.
    private var curlEdge: some View {
        ZStack(alignment: .bottom) {
            // Shadow the curl casts just beneath itself.
            LinearGradient(
                colors: [.clear, .black.opacity(0.18)],
                startPoint: .top, endPoint: .bottom
            )
            .frame(height: 18)
            // The curled lip: a highlight band capped by a soft fold line.
            VStack(spacing: 0) {
                LinearGradient(
                    colors: [Color.white.opacity(0.0), Color.white],
                    startPoint: .top, endPoint: .bottom
                )
                .frame(height: 7)
                Rectangle()
                    .fill(Color.black.opacity(0.28))
                    .frame(height: 1.5)
            }
        }
    }

    // MARK: - Paper

    private var receiptPaper: some View {
        receiptBody
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 22)
            .frame(width: paperWidth, alignment: .top)
            .background(
                ReceiptSlip(toothWidth: 12, toothHeight: 7, torn: done)
                    .fill(.white)
                    .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 4)
            )
            // The slip is always white thermal paper, so its text must stay dark
            // even in dark mode — otherwise .primary/.secondary invert to white
            // and the values vanish. Pin the printed content to light.
            .environment(\.colorScheme, .light)
    }

    /// Hidden, natural-size render used only to measure the paper's height.
    private var measuringCopy: some View {
        receiptPaper
            .fixedSize(horizontal: false, vertical: true)
            .hidden()
            .allowsHitTesting(false)
            .background(
                GeometryReader { geo in
                    Color.clear
                        .onAppear { if paperHeight == 0 { paperHeight = geo.size.height } }
                }
            )
    }

    /// The receipt as an ordered list of rows. VoiceOver reads the whole slip
    /// as one element; decorative separators and the barcode are hidden below.
    private var receiptBody: some View {
        VStack(spacing: 8) {
            ForEach(rows.indices, id: \.self) { i in
                rows[i]
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var rows: [AnyView] {
        var r: [AnyView] = []
        r.append(AnyView(
            Text("TEAROFF")
                .font(.system(.title3, design: .monospaced).weight(.bold))
                .tracking(6)
        ))
        r.append(AnyView(dashed))
        r.append(AnyView(line("MERCHANT", purchase.merchant.isEmpty ? "—" : purchase.merchant)))
        r.append(AnyView(line("DATE", purchase.purchaseDate.formatted(date: .abbreviated, time: .omitted))))
        r.append(AnyView(line("CATEGORY", purchase.category.displayName)))
        r.append(AnyView(dashed))
        r.append(AnyView(line("TOTAL", purchase.totalCents.formatted(currencyCode: "USD"), emphasized: true)))
        if let w = returnWindow {
            r.append(AnyView(dashed))
            r.append(AnyView(stacked("RETURN BY",
                                     w.deadline.formatted(date: .abbreviated, time: .omitted),
                                     w.provenance.explanation,
                                     estimate: w.provenance.isEstimate)))
        }
        if let w = warrantyWindow {
            r.append(AnyView(dashed))
            r.append(AnyView(stacked("WARRANTY UNTIL",
                                     w.deadline.formatted(date: .abbreviated, time: .omitted),
                                     w.provenance.explanation,
                                     estimate: w.provenance.isEstimate)))
        }
        r.append(AnyView(solid))
        r.append(AnyView(Barcode(seed: purchase.id).frame(height: 42).padding(.top, 2)
            .accessibilityHidden(true)))
        r.append(AnyView(
            Text("THANK YOU")
                .font(.system(.caption2, design: .monospaced))
                .tracking(3)
                .foregroundStyle(.secondary)
        ))
        return r
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
            .accessibilityHidden(true)
    }

    private var solid: some View {
        Text(String(repeating: "=", count: 30))
            .font(.system(.caption2, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .accessibilityHidden(true)
    }

    // MARK: - Animation driver

    private func startPrinting() {
        NSLog("🧾TEAROFF startPrinting — progress=\(progress) reduceMotion=\(reduceMotion) paperHeight=\(paperHeight)")
        guard progress == 0 else { return }
        if reduceMotion {
            progress = 1
            done = true
            return
        }
        // Blink the feed light while paper advances.
        withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) {
            feedBlink = true
        }
        // Tiny rapid vertical stepping — the paper advancing over the feed
        // roller, not gliding smoothly.
        withAnimation(.linear(duration: 0.07).repeatForever(autoreverses: true)) {
            jitter = 1.5
        }
        // The sheet feeds out and decelerates as it comes to rest.
        let feedDuration = 2.0
        withAnimation(.easeOut(duration: feedDuration)) {
            progress = 1
        }

        // Flip to the finished state on a fixed timer rather than the feed
        // animation's completion callback. The repeating `jitter` keeps the
        // paper's offset perpetually in motion, which can stop that callback
        // from ever firing — leaving `done` false and the Done button stuck
        // disabled. A timer guarantees the button becomes tappable.
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(feedDuration))
            guard !done else { return }
            feedBlink = false
            // Stop the feed stepping and drop the tear-off edge.
            withAnimation(.easeOut(duration: 0.15)) { jitter = 0 }
            withAnimation(.easeInOut(duration: 0.2)) { done = true }
            NSLog("🧾TEAROFF done flipped to true — button now enabled")
            // The freed strip swings once under its own weight and settles —
            // an underdamped pendulum hinged at the slot. Low `bounce` keeps
            // the settle weighted and premium rather than springy-toy.
            sway = 6
            withAnimation(.interpolatingSpring(duration: 0.9, bounce: 0.22)) {
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
