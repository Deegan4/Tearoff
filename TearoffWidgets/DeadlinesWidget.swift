import WidgetKit
import SwiftUI
import VaultCore

/// One timeline entry: the digest the app last published, plus the moment the
/// entry represents (so day-counts recompute across midnight).
struct DeadlinesEntry: TimelineEntry {
    let date: Date
    let digest: DeadlineDigest
}

struct DeadlinesProvider: TimelineProvider {
    private let store = SharedDigestStore()

    func placeholder(in context: Context) -> DeadlinesEntry {
        DeadlinesEntry(date: Date(), digest: Self.sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (DeadlinesEntry) -> Void) {
        let digest = store.read() ?? (context.isPreview ? Self.sample : DeadlineDigest(generatedAt: Date(), deadlines: []))
        completion(DeadlinesEntry(date: Date(), digest: digest))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<DeadlinesEntry>) -> Void) {
        let now = Date()
        let digest = store.read() ?? DeadlineDigest(generatedAt: now, deadlines: [])
        // Recompute at the next midnight so day-remaining counts stay accurate
        // even if the app doesn't reload us first.
        let nextMidnight = Calendar.current.startOfDay(for: now.addingTimeInterval(24 * 60 * 60))
        let entry = DeadlinesEntry(date: now, digest: digest)
        completion(Timeline(entries: [entry], policy: .after(nextMidnight)))
    }

    static let sample = DeadlineDigest(generatedAt: Date(), deadlines: [
        UpcomingDeadline(id: "s1", merchant: "Best Buy", kind: .returnWindow,
                         deadline: Date().addingTimeInterval(3 * 86400), isEstimate: false),
        UpcomingDeadline(id: "s2", merchant: "Home Depot", kind: .warranty,
                         deadline: Date().addingTimeInterval(40 * 86400), isEstimate: true),
    ])
}

struct DeadlinesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "TearoffDeadlines", provider: DeadlinesProvider()) { entry in
            DeadlinesWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Upcoming Deadlines")
        .description("Return and warranty windows closing soon.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct DeadlinesWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: DeadlinesEntry

    private var rows: [UpcomingDeadline] {
        Array(entry.digest.deadlines.prefix(family == .systemSmall ? 1 : 4))
    }

    var body: some View {
        if entry.digest.isLocked {
            lockedState
        } else if rows.isEmpty {
            emptyState
        } else if family == .systemSmall {
            small
        } else {
            medium
        }
    }

    private var lockedState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Tearoff", systemImage: "lock.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Spacer()
            Text("Widgets are a Pro feature")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("Tearoff", systemImage: "checkmark.seal.fill")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            Spacer()
            Text("No deadlines coming up")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var small: some View {
        let d = rows[0]
        let days = DeadlineDigest.daysRemaining(to: d.deadline, from: entry.date)
        return VStack(alignment: .leading, spacing: 6) {
            Text(d.kind.label.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(color(for: days))
            Text(d.merchant)
                .font(.headline)
                .lineLimit(1)
            Spacer()
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(countdown(days))
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(color(for: days))
                        .contentTransition(.numericText())
                    Text(d.deadline.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                // Only return windows can be "returned"; warranties can't.
                if d.kind == .returnWindow, let pid = d.purchaseID {
                    Spacer()
                    markReturnedButton(pid, label: "Mark \(d.merchant) returned")
                        .font(.title2)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Closing soon", systemImage: "clock.badge.exclamationmark")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tint)
            ForEach(rows) { d in
                let days = DeadlineDigest.daysRemaining(to: d.deadline, from: entry.date)
                HStack(spacing: 8) {
                    Image(systemName: d.kind == .returnWindow ? "arrow.uturn.backward" : "shield.lefthalf.filled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(width: 16)
                    Text(d.merchant).font(.caption).lineLimit(1)
                    if d.isEstimate {
                        Image(systemName: "questionmark.circle").font(.caption2).foregroundStyle(.orange)
                    }
                    Spacer(minLength: 4)
                    Text(countdown(days))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(color(for: days))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    if d.kind == .returnWindow, let pid = d.purchaseID {
                        markReturnedButton(pid, label: "Mark \(d.merchant) returned")
                            .font(.callout)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    /// The interactive "returned" control. Runs `MarkReturnedIntent` in place —
    /// the widget updates without launching the app (see the intent's notes).
    private func markReturnedButton(_ purchaseID: String, label: String) -> some View {
        Button(intent: MarkReturnedIntent(purchaseID: purchaseID)) {
            Image(systemName: "checkmark.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.green)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func countdown(_ days: Int) -> String {
        switch days {
        case ..<0: "Passed"
        case 0: "Today"
        case 1: "1 day"
        default: "\(days) days"
        }
    }

    private func color(for days: Int) -> Color {
        switch days {
        case ..<0: .secondary
        case 0...2: .red
        case 3...7: .orange
        default: .green
        }
    }
}
