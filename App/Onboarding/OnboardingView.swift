import SwiftUI
import VaultCore

/// First-launch introduction. Shown once via `.hasCompletedOnboarding`;
/// swipeable pages walk through the core loop (track → print → alert) before
/// landing on a free-vs-Pro summary.
///
/// Every page shows a *mockup of the real product* rather than a decorative
/// icon — a fanned stack of deadline cards, the live thermal-printer replay,
/// an actual alert banner, and the real Pro list. A new user sees what they're
/// getting before they've added a single receipt.
struct OnboardingView: View {
    @AppStorage(OnboardingView.storageKey) private var hasCompletedOnboarding = false
    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        ZStack {
            OnboardingBackdrop(page: page)

            VStack(spacing: 0) {
                TabView(selection: $page) {
                    OnboardingPage(
                        title: "You own this now",
                        subtitle: "It wasn't right. The receipt went in a drawer. The window closed on Tuesday. Congratulations — it's yours forever.",
                        isActive: page == 0
                    ) { ExpiredReceiptMock(isActive: page == 0) }
                        .tag(0)

                    OnboardingPage(
                        title: "Now you know the exact day",
                        subtitle: "Tearoff reads the receipt, checks the store's policy, and prints the day your window shuts. No more \"I think it's thirty days?\"",
                        isActive: page == 1
                    ) { MiniReceiptPrinter(isActive: page == 1) }
                        .tag(1)

                    OnboardingPage(
                        title: "Then we nag you. Politely.",
                        subtitle: "A nudge while you can still walk back into the store — not a respectful moment of silence after the window closes.",
                        isActive: page == 2
                    ) { AlertBannerMock(isActive: page == 2) }
                        .tag(2)

                    OnboardingPage(
                        title: "Free forever. Pro if you're fancy.",
                        subtitle: "Receipts, deadlines, and alerts cost nothing — that's the app, not a trial. Pro does the typing for you, and your first \(ScanAllowance.freeLimit) scans are on the house.",
                        isActive: page == 3
                    ) { ProFeatureList(isActive: page == 3) }
                        .tag(3)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                dots

                Button(page == pageCount - 1 ? "Get Started" : "Continue") {
                    if page == pageCount - 1 {
                        hasCompletedOnboarding = true
                    } else {
                        withAnimation(Motion.premium) { page += 1 }
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .buttonStyle(.glass)
                .tint(.blue)
                .padding(.horizontal)
                .padding(.bottom, 24)
            }
        }
    }

    private var dots: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { i in
                Capsule()
                    .fill(i == page ? Color.accentColor : Color.secondary.opacity(0.25))
                    .frame(width: i == page ? 20 : 7, height: 7)
                    .animation(Motion.snappy, value: page)
            }
        }
        .padding(.bottom, 20)
    }
}

// MARK: - Chrome

/// A soft, slowly drifting color wash behind every page. The hue shifts per
/// page so swiping feels like moving through distinct rooms rather than
/// sliding text over a flat background.
private struct OnboardingBackdrop: View {
    let page: Int

    private var tint: Color {
        switch page {
        case 0: .blue
        case 1: .indigo
        case 2: .orange
        default: .green
        }
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Color(.systemBackground)

            // A mesh gradient drifts like weather instead of sitting still —
            // it gives the flat pages depth without competing with the
            // product mockups, which are the actual subject.
            if reduceMotion {
                mesh(phase: 0)
            } else {
                TimelineView(.animation) { context in
                    mesh(phase: context.date.timeIntervalSinceReferenceDate)
                }
            }

            // Darkened edges pull the eye to the centre where the mockup and
            // copy live.
            RadialGradient(
                colors: [.clear, .black.opacity(0.28)],
                center: .center, startRadius: 200, endRadius: 560
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .animation(.easeInOut(duration: 0.55), value: page)
        .ignoresSafeArea()
    }

    /// 3×3 mesh, top-weighted in the page tint and fading to nothing at the
    /// bottom. Only the edge midpoints and centre drift — the four corners are
    /// pinned, since moving those warps the whole field rather than stirring it.
    private func mesh(phase: TimeInterval) -> some View {
        func drift(_ seed: Double, _ amplitude: Float) -> Float {
            Float(sin(phase * 0.22 + seed)) * amplitude
        }

        return MeshGradient(
            width: 3,
            height: 3,
            points: [
                SIMD2<Float>(0, 0),
                SIMD2<Float>(0.5 + drift(0, 0.07), 0),
                SIMD2<Float>(1, 0),

                SIMD2<Float>(0, 0.45 + drift(1.7, 0.05)),
                SIMD2<Float>(0.5 + drift(3.1, 0.09), 0.5 + drift(4.6, 0.07)),
                SIMD2<Float>(1, 0.55 + drift(2.4, 0.05)),

                SIMD2<Float>(0, 1),
                SIMD2<Float>(0.5 + drift(5.2, 0.06), 1),
                SIMD2<Float>(1, 1),
            ],
            colors: [
                tint.opacity(0.50), tint.opacity(0.38), tint.opacity(0.22),
                tint.opacity(0.26), tint.opacity(0.16), tint.opacity(0.08),
                .clear, .clear, .clear,
            ]
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

/// Shared page scaffold: a visual up top, then title and subtitle. Text
/// cascades in each time the page becomes active so swiping back replays it.
private struct OnboardingPage<Visual: View>: View {
    let title: String
    let subtitle: String
    let isActive: Bool
    @ViewBuilder var visual: Visual

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            visual
                .frame(height: 290)
                // Pool of light under the mockup so it reads as sitting *in*
                // the scene rather than pasted on top of a flat field.
                .background {
                    Ellipse()
                        .fill(
                            RadialGradient(
                                colors: [.white.opacity(0.16), .clear],
                                center: .center, startRadius: 2, endRadius: 190
                            )
                        )
                        .frame(height: 240)
                        .blur(radius: 26)
                        .opacity(isActive ? 1 : 0)
                        .allowsHitTesting(false)
                }
                .scaleEffect(isActive ? 1 : 0.92)
                .opacity(isActive ? 1 : 0)
                // Incoming pages settle up into place; outgoing ones sink.
                .offset(y: isActive ? 0 : 10)
                .animation(Motion.alive, value: isActive)
            // Fixed gap so the visual and its caption read as one unit; the
            // flexible space all lives outside the pair.
            Spacer().frame(height: 28)
            VStack(spacing: 12) {
                Text(title)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .staggeredAppear(0)
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .staggeredAppear(1)
            }
            Spacer(minLength: 0)
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
    }
}

// MARK: - Page 1: the problem

/// The pain, staged: a jacket receipt sitting in a drawer while its countdown
/// ticks 3 → 2 → 1 → 0 and the card goes grey and stamped. This is the whole
/// reason the app exists, so the first thing a user sees is the thing that
/// already happened to them.
private struct ExpiredReceiptMock: View {
    let isActive: Bool

    /// One "you missed it" scenario. A single canned example on repeat reads
    /// as a screenshot; rotating through categories and price points makes the
    /// problem feel like something that happens to *everyone*, repeatedly.
    struct Scenario {
        let merchant: String
        let item: String
        let price: String
    }

    static let scenarios: [Scenario] = [
        .init(merchant: "Northline Outfitters", item: "Wool jacket — one size too small", price: "$84.00"),
        .init(merchant: "Best Buy", item: "Soundbar — sounded better in the store", price: "$249.99"),
        .init(merchant: "IKEA", item: "Desk lamp — wrong shade of white", price: "$39.00"),
        .init(merchant: "The Home Depot", item: "Tile saw — job finished without it", price: "$159.00"),
        .init(merchant: "Nordstrom", item: "Boots — they pinch", price: "$129.00"),
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var daysLeft = 3
    @State private var expired = false
    @State private var stampShown = false
    @State private var scenarioIndex = 0
    @State private var loopTask: Task<Void, Never>?

    private var scenario: Scenario {
        Self.scenarios[scenarioIndex % Self.scenarios.count]
    }

    var body: some View {
        ZStack {
            card
                .rotationEffect(.degrees(expired ? -3 : 0))
                .animation(Motion.premium, value: expired)
            if stampShown { stamp.transition(.scale(scale: 1.6).combined(with: .opacity)) }
        }
        .onChange(of: isActive) { _, active in
            if active { start() } else { stop() }
        }
        .onAppear { if isActive { start() } }
        .onDisappear { stop() }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(scenario.merchant)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .contentTransition(.opacity)
                Spacer(minLength: 8)
                Text(scenario.price)
                    .font(.subheadline.monospacedDigit())
                    .contentTransition(.opacity)
            }
            Text(scenario.item)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .contentTransition(.opacity)

            Divider().opacity(0.5)

            HStack(spacing: 6) {
                Image(systemName: expired ? "xmark.circle.fill" : "clock.badge.exclamationmark")
                    .font(.footnote)
                    .symbolEffect(.pulse, options: .repeating, isActive: !expired)
                Text(expired ? "Return window closed" : "Return within \(daysLeft) day\(daysLeft == 1 ? "" : "s")")
                    .font(.footnote.weight(.medium))
                    .contentTransition(.numericText(countsDown: true))
            }
            .foregroundStyle(expired ? Color.secondary : .red)
        }
        .padding(16)
        .frame(width: 272, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .overlay(
            RoundedRectangle(cornerRadius: 18)
                .strokeBorder(.white.opacity(0.10), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 14, y: 8)
        .saturation(expired ? 0.15 : 1)
        .opacity(expired ? 0.55 : 1)
        .animation(Motion.premium, value: expired)
    }

    private var stamp: some View {
        Text("TOO LATE")
            .font(.system(size: 26, weight: .heavy, design: .rounded))
            .tracking(2)
            .foregroundStyle(.red.opacity(0.85))
            .padding(.horizontal, 14).padding(.vertical, 7)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(.red.opacity(0.85), lineWidth: 3)
            )
            .rotationEffect(.degrees(-12))
            .shadow(color: .red.opacity(0.35), radius: 10)
    }

    private func start() {
        guard loopTask == nil else { return }
        if reduceMotion {
            daysLeft = 0; expired = true; stampShown = true
            return
        }
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                // Reset, then let the clock run out on them.
                withAnimation(Motion.snappy) { stampShown = false }
                expired = false
                daysLeft = 3
                try? await Task.sleep(for: .seconds(0.9))

                for day in [2, 1] {
                    if Task.isCancelled { break }
                    withAnimation(Motion.snappy) { daysLeft = day }
                    try? await Task.sleep(for: .seconds(0.75))
                }
                if Task.isCancelled { break }

                withAnimation(Motion.premium) { expired = true }
                try? await Task.sleep(for: .seconds(0.25))
                withAnimation(.spring(response: 0.34, dampingFraction: 0.62, blendDuration: 0)) {
                    stampShown = true
                }
                try? await Task.sleep(for: .seconds(2.4))

                // Advance only at the end of a full cycle, so the first thing
                // a new user sees is scenario 0 and the swap always lands
                // between rounds rather than mid-countdown.
                withAnimation(Motion.premium) { scenarioIndex += 1 }
            }
        }
    }

    private func stop() {
        loopTask?.cancel()
        loopTask = nil
        stampShown = false
        expired = false
        daysLeft = 3
    }
}

// MARK: - Page 3: alert banner

/// A mock iOS notification banner that slides in, waits, and slides back out
/// on a loop — the actual thing the user will see on their lock screen.
private struct AlertBannerMock: View {
    let isActive: Bool

    /// One alert the app actually sends. Rotating these shows the range —
    /// returns *and* warranties, a comfortable heads-up *and* a last-day
    /// warning — instead of implying Tearoff only ever says one thing.
    struct Alert {
        let title: String
        let body: String
    }

    static let alerts: [Alert] = [
        .init(title: "Return window closing",
              body: "Your Northline Outfitters return window closes in 3 days."),
        .init(title: "Last day to return",
              body: "Today is the final day to return the IKEA desk lamp."),
        .init(title: "Return window closing",
              body: "Best Buy — 2 days left to return the soundbar."),
        .init(title: "Warranty expiring",
              body: "Your Home Depot tile saw's warranty ends in 30 days."),
    ]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown = false
    @State private var alertIndex = 0
    @State private var loopTask: Task<Void, Never>?

    private var alert: Alert {
        Self.alerts[alertIndex % Self.alerts.count]
    }

    var body: some View {
        // Centered in the visual slot (rather than pinned to the top) so the
        // page doesn't open on a void; it still drops in from above, which is
        // how a real banner arrives.
        banner
            .offset(y: shown ? 0 : -140)
            .opacity(shown ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.78, blendDuration: 0), value: shown)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onChange(of: isActive) { _, active in
            if active { start() } else { stop() }
        }
        .onAppear { if isActive { start() } }
        .onDisappear { stop() }
    }

    private var banner: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 9)
                .fill(LinearGradient(colors: [.blue, .indigo], startPoint: .top, endPoint: .bottom))
                .frame(width: 38, height: 38)
                .overlay(
                    Image(systemName: "receipt")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                )
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text("TEAROFF")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("now")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(alert.title)
                    .font(.subheadline.weight(.semibold))
                    .contentTransition(.opacity)
                Text(alert.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .contentTransition(.opacity)
            }
        }
        .padding(12)
        .frame(width: 300, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .strokeBorder(.white.opacity(0.12), lineWidth: 0.5)
        )
        .shadow(color: .black.opacity(0.28), radius: 16, y: 8)
    }

    private func start() {
        guard loopTask == nil else { return }
        // Reduce Motion: show one banner, already landed. A 140pt slide is
        // exactly the kind of movement the setting exists to suppress.
        if reduceMotion {
            shown = true
            return
        }
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                shown = true
                try? await Task.sleep(for: .seconds(2.6))
                if Task.isCancelled { break }
                shown = false
                // Swap the content only once the banner has slid off-screen,
                // so the text never visibly morphs in place.
                try? await Task.sleep(for: .seconds(0.55))
                alertIndex += 1
                try? await Task.sleep(for: .seconds(0.35))
            }
        }
    }

    private func stop() {
        loopTask?.cancel()
        loopTask = nil
        shown = false
    }
}

// MARK: - Page 4: Pro feature list

/// The real Pro list, cascading in — same features the paywall sells, so the
/// last onboarding page and the paywall tell one consistent story.
private struct ProFeatureList: View {
    let isActive: Bool
    @State private var shown = false

    private let features: [(icon: String, label: String)] = [
        ("camera.viewfinder", "Camera receipt scanning"),
        ("shield.lefthalf.filled", "Warranty tracking"),
        ("widget.small", "Home Screen widgets"),
        ("location", "Proximity reminders"),
        ("square.and.arrow.up", "CSV + yearly PDF export"),
    ]

    var body: some View {
        VStack(spacing: 10) {
            Text("PRO")
                .font(.caption.weight(.bold))
                .tracking(3)
                .foregroundStyle(.tint)
                .padding(.horizontal, 12).padding(.vertical, 5)
                .background(.tint.opacity(0.14), in: Capsule())
                .padding(.bottom, 4)
                .accessibilityLabel("Pro features")

            ForEach(Array(features.enumerated()), id: \.offset) { index, feature in
                HStack(spacing: 12) {
                    Image(systemName: feature.icon)
                        .font(.footnote)
                        .foregroundStyle(.tint)
                        .frame(width: 22)
                    Text(feature.label)
                        .font(.subheadline)
                    Spacer(minLength: 0)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(width: 290, alignment: .leading)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                .opacity(shown ? 1 : 0)
                .offset(y: shown ? 0 : 16)
                .animation(Motion.alive.delay(Double(index) * 0.07), value: shown)
            }
        }
        .onChange(of: isActive) { _, active in shown = active }
        .onAppear { shown = isActive }
    }
}

// MARK: - Page 2: looping thermal printer

/// Self-contained, looping miniature of the ReceiptPrintView "thermal
/// printer" motion — demo data only, no purchase model required. Replays
/// automatically while `isActive`, and resets when swiped away so it's ready
/// to play again on return.
private struct MiniReceiptPrinter: View {
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var progress: CGFloat = 0    // 0 tucked in slot, 1 fully printed
    @State private var sway: Double = 0
    @State private var jitter: CGFloat = 0
    @State private var torn = false
    @State private var feedBlink = false
    @State private var loopTask: Task<Void, Never>?

    private let paperWidth: CGFloat = 190
    private let paperHeight: CGFloat = 200

    var body: some View {
        VStack(spacing: 0) {
            printer.zIndex(1)

            ZStack(alignment: .top) {
                receiptPaper
                    .offset(y: -paperHeight * (1 - progress) + jitter)
            }
            .frame(width: paperWidth, height: paperHeight, alignment: .top)
            .clipped()
            .shadow(color: .black.opacity(0.16), radius: 8, x: 0, y: 6)
            .padding(.top, -6)
        }
        .rotationEffect(.degrees(sway), anchor: .top)
        .onAppear { if isActive { startLoop() } }
        .onChange(of: isActive) { _, active in
            if active { startLoop() } else { stopLoop() }
        }
        .onDisappear { stopLoop() }
    }

    private var printer: some View {
        let bodyWidth = paperWidth + 56
        return ZStack {
            VStack(spacing: 0) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(colors: [Color(white: 0.40), Color(white: 0.24)], startPoint: .top, endPoint: .bottom))
                    .frame(width: bodyWidth - 14, height: 16)
                    .offset(y: 5)
                UnevenRoundedRectangle(cornerRadii: .init(topLeading: 5, bottomLeading: 14, bottomTrailing: 14, topTrailing: 5))
                    .fill(LinearGradient(colors: [Color(white: 0.30), Color(white: 0.15)], startPoint: .top, endPoint: .bottom))
                    .frame(width: bodyWidth, height: 38)
            }
            .shadow(color: .black.opacity(0.35), radius: 6, y: 3)

            Circle()
                .fill(torn ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
                .opacity(feedBlink ? 1 : 0.3)
                .shadow(color: (torn ? Color.green : Color.orange).opacity(0.8), radius: feedBlink ? 3 : 0)
                .offset(x: -bodyWidth / 2 + 24, y: 5)

            RoundedRectangle(cornerRadius: 2)
                .fill(LinearGradient(colors: [.black, Color(white: 0.12)], startPoint: .top, endPoint: .bottom))
                .frame(width: paperWidth + 14, height: 6)
                .offset(y: 20)
        }
    }

    private var receiptPaper: some View {
        VStack(spacing: 6) {
            Text("TEAROFF")
                .font(.system(.caption, design: .monospaced).weight(.bold))
                .tracking(4)
            demoDashed
            demoLine("MERCHANT", "Northline Outfitters")
            demoLine("TOTAL", "$84.00", emphasized: true)
            demoDashed
            VStack(spacing: 1) {
                Text("RETURN BY")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text("Aug 24")
                    .font(.system(.callout, design: .monospaced).weight(.semibold))
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 18)
        .frame(width: paperWidth, alignment: .top)
        .background(
            MiniReceiptSlip(toothWidth: 10, toothHeight: 6, torn: torn)
                .fill(.white)
                .shadow(color: .black.opacity(0.18), radius: 5, x: 0, y: 3)
        )
        .environment(\.colorScheme, .light)
    }

    private func demoLine(_ label: String, _ value: String, emphasized: Bool = false) -> some View {
        HStack {
            Text(label).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.system(emphasized ? .callout : .caption2, design: .monospaced).weight(emphasized ? .bold : .regular))
        }
    }

    private var demoDashed: some View {
        Text(String(repeating: "-", count: 22))
            .font(.system(size: 9, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
    }

    private func startLoop() {
        guard loopTask == nil else { return }
        if reduceMotion {
            progress = 1
            torn = true
            return
        }
        loopTask = Task { @MainActor in
            while !Task.isCancelled {
                progress = 0
                torn = false
                sway = 0
                withAnimation(.easeInOut(duration: 0.3).repeatForever(autoreverses: true)) { feedBlink = true }
                withAnimation(.linear(duration: 0.07).repeatForever(autoreverses: true)) { jitter = 1.2 }
                withAnimation(.easeOut(duration: 1.4)) { progress = 1 }

                try? await Task.sleep(for: .seconds(1.4))
                if Task.isCancelled { break }
                feedBlink = false
                withAnimation(.easeOut(duration: 0.12)) { jitter = 0 }
                withAnimation(.easeInOut(duration: 0.18)) { torn = true }
                sway = 6
                withAnimation(.interpolatingSpring(duration: 0.8, bounce: 0.22)) { sway = 0 }

                try? await Task.sleep(for: .seconds(1.6))
            }
        }
    }

    private func stopLoop() {
        loopTask?.cancel()
        loopTask = nil
        feedBlink = false
        jitter = 0
    }
}

private struct MiniReceiptSlip: Shape {
    var toothWidth: CGFloat = 10
    var toothHeight: CGFloat = 6
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

extension OnboardingView {
    static let storageKey = "hasCompletedOnboarding"
}

#Preview {
    OnboardingView()
}
