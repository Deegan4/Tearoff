import SwiftUI
import VaultCore

/// The vault-keeper rank badge: title, joke, and progress to the next rung.
///
/// Purely cosmetic. It never gates a feature or changes a deadline — if this
/// view were deleted the app would behave identically, which is the point.
struct RankCard: View {
    let progress: RankProgress

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Drives the bar fill on appear so it reads as a measure, not a label.
    @State private var filled = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: progress.rank.symbolName)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32)
                    .symbolEffect(.bounce, options: .repeat(.periodic(delay: 4)))

                VStack(alignment: .leading, spacing: 2) {
                    Text(progress.rank.title)
                        .font(.headline)
                    Text("Level \(progress.rank.level) · \(progress.xp) XP")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }

            Text(progress.rank.blurb)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            ProgressView(value: filled ? progress.fractionToNext : 0)
                .tint(Color.accentColor)
                .animation(reduceMotion ? nil : Motion.reveal, value: filled)
                .animation(reduceMotion ? nil : Motion.reveal, value: progress.fractionToNext)

            if let next = progress.next, let toNext = progress.xpToNext {
                Text("\(toNext) XP to \(next.title)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            } else {
                Text("Ladder complete. Nothing left to prove.")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
        .onAppear { filled = true }
        // One combined announcement — VoiceOver should read the rank as a
        // status, not as four disconnected fragments.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(progress.rank.title), level \(progress.rank.level)")
        .accessibilityValue(
            progress.isMaxRank
                ? "\(progress.xp) XP. Highest rank reached."
                : "\(progress.xp) XP. \(progress.xpToNext ?? 0) to the next rank."
        )
    }
}

/// The level-up moment: a short, self-aware promotion notice.
///
/// Deliberately a plain sheet rather than confetti — the app's humour is
/// deadpan, and a bureaucratic promotion letter is funnier than a party.
struct LevelUpView: View {
    let rank: VaultRank
    var onDismiss: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var revealed = false

    var body: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: rank.symbolName)
                .font(.system(size: 64))
                .foregroundStyle(.tint)
                .scaleEffect(revealed || reduceMotion ? 1 : 0.6)
                .opacity(revealed ? 1 : 0)
                .symbolEffect(.bounce, value: revealed)

            VStack(spacing: 8) {
                Text("PROMOTED")
                    .font(.system(.caption, design: .monospaced).weight(.bold))
                    .tracking(4)
                    .foregroundStyle(.secondary)

                Text(rank.title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Level \(rank.level)")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.tint)
                    .monospacedDigit()

                Text(rank.blurb)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 4)
            }
            .opacity(revealed ? 1 : 0)
            .offset(y: revealed || reduceMotion ? 0 : 12)
            .padding(.horizontal, 32)

            Spacer()

            Button {
                dismiss()
                onDismiss()
            } label: {
                Text("Back to work")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.glass)
            .tint(.blue)
            .padding(.horizontal, 32)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .onAppear {
            withAnimation(reduceMotion ? nil : Motion.reveal) { revealed = true }
        }
        .sensoryFeedback(.success, trigger: revealed)
    }
}

#Preview("Rank card — mid ladder") {
    Form {
        Section {
            RankCard(progress: RankLadder.progress(
                purchasesTracked: 22, scansConfirmed: 9, returnsCompleted: 3))
        }
    }
}

#Preview("Rank card — max rank") {
    Form {
        Section {
            RankCard(progress: RankLadder.progress(xp: 99_999))
        }
    }
}

#Preview("Level up") {
    LevelUpView(rank: RankLadder.ranks[4])
}
