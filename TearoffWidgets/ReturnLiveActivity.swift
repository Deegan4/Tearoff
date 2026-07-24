import ActivityKit
import WidgetKit
import SwiftUI

/// Lock Screen + Dynamic Island rendering of the return-countdown Live
/// Activity. Uses SwiftUI's live `Text(timerInterval:)` / relative style so the
/// countdown ticks without the app pushing updates.
struct ReturnLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ReturnActivityAttributes.self) { context in
            lockScreen(context)
                .padding()
                .activityBackgroundTint(Color.teal.opacity(0.18))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("Return", systemImage: "arrow.uturn.backward")
                        .font(.caption).foregroundStyle(.tint)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.deadline, style: .relative)
                        .font(.caption.monospacedDigit())
                        .multilineTextAlignment(.trailing)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(context.attributes.merchant).font(.headline).lineLimit(1)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Return window closes \(context.state.deadline, style: .date)")
                        .font(.caption2).foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "arrow.uturn.backward").foregroundStyle(.tint)
            } compactTrailing: {
                Text(context.state.deadline, style: .timer)
                    .frame(maxWidth: 44)
                    .font(.caption2.monospacedDigit())
            } minimal: {
                Image(systemName: "clock.badge.exclamationmark").foregroundStyle(.orange)
            }
        }
    }

    private func lockScreen(_ context: ActivityViewContext<ReturnActivityAttributes>) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.title)
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Return \(context.attributes.merchant)")
                    .font(.headline).lineLimit(1)
                Text("Closes \(context.state.deadline, style: .date)")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(context.state.deadline, style: .timer)
                .font(.title3.weight(.semibold).monospacedDigit())
                .foregroundStyle(.orange)
                .frame(maxWidth: 88)
        }
    }
}
