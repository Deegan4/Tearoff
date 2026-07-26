import SwiftUI

/// First-launch introduction. Shown once via `.hasCompletedOnboarding`;
/// swipeable pages walk through the core loop (scan → print → track → alert)
/// before landing on a free-vs-Pro summary. One page hosts a live, looping
/// replay of the thermal-printer receipt animation so the app's signature
/// moment sells itself before anyone's added a purchase.
struct OnboardingView: View {
    @AppStorage(OnboardingView.storageKey) private var hasCompletedOnboarding = false
    @State private var page = 0

    private let pageCount = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                OnboardingPageView(
                    icon: "receipt",
                    title: "Never miss a return window",
                    subtitle: "Tearoff tracks every receipt's return and warranty deadline, so nothing quietly expires in a drawer.",
                    isActive: page == 0
                )
                .tag(0)

                OnboardingPrinterPage(isActive: page == 1)
                    .tag(1)

                OnboardingPageView(
                    icon: "bell.badge",
                    title: "Get a nudge before it's too late",
                    subtitle: "Alerts land while there's still time to act — Pro adds a nudge if you're back near the store, too.",
                    isActive: page == 2
                )
                .tag(2)

                OnboardingPageView(
                    icon: "checkmark.seal",
                    title: "Free forever, Pro when you want it",
                    subtitle: "Manual receipts, alerts, and your full vault are free. Pro adds camera + AI extraction, warranty tracking, proximity reminders, direct return links, and export — CSV or a yearly PDF report.",
                    isActive: page == 3
                )
                .tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(Motion.reveal, value: page)

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

/// A single icon + headline + subtitle page. The icon plays a bounce symbol
/// effect and the text cascades in via `staggeredAppear` each time the page
/// becomes active (rather than once on first layout), so swiping back to it
/// replays the motion instead of showing static content.
private struct OnboardingPageView: View {
    let icon: String
    let title: String
    let subtitle: String
    let isActive: Bool

    @State private var bounce = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 72))
                .foregroundStyle(.tint)
                .symbolEffect(.bounce, value: bounce)
                .scaleEffect(isActive ? 1 : 0.7)
                .opacity(isActive ? 1 : 0)
                .animation(Motion.alive, value: isActive)
            Text(title)
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
                .staggeredAppear(0)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .staggeredAppear(1)
            Spacer()
            Spacer()
        }
        .padding(.horizontal)
        .onChange(of: isActive) { _, active in
            if active { bounce.toggle() }
        }
        .onAppear { if isActive { bounce.toggle() } }
    }
}

/// The onboarding page that shows off the signature moment: a scaled-down,
/// self-looping replay of the thermal-printer receipt feed, so a new user
/// sees the payoff before they've ever added a purchase.
private struct OnboardingPrinterPage: View {
    let isActive: Bool

    var body: some View {
        VStack(spacing: 16) {
            Spacer(minLength: 8)
            MiniReceiptPrinter(isActive: isActive)
                .frame(height: 320)
            Text("Watch it print")
                .font(.title2.weight(.semibold))
                .staggeredAppear(0)
            Text("Every purchase gets its own printed slip — deadline included.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .staggeredAppear(1)
            Spacer()
        }
        .padding(.horizontal)
    }
}

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
    private let paperHeight: CGFloat = 210

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
