import SwiftUI
import VaultCore

/// Settings, currently home to the on-device scan-accuracy dashboard. The
/// numbers are aggregated locally from every confirmed scan — how often the
/// scanner got each field right before the user touched it — so accuracy
/// improvement is a measured loop, not guesswork.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    // Observed so the dashboard reflects new scans live.
    private var telemetry = ExtractionTelemetryStore.shared
    @State private var confirmingReset = false

    private var ledger: AccuracyLedger { telemetry.ledger }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Scans confirmed", value: "\(ledger.scanCount)")
                    LabeledContent("Overall accuracy") {
                        Text(percentText(ledger.overallAccuracy))
                            .foregroundStyle(accuracyColor(ledger.overallAccuracy))
                            .monospacedDigit()
                    }
                } header: {
                    Text("Scan accuracy")
                } footer: {
                    Text("Measured on this device from each scan you confirm. A field only counts once the scanner filled it in, so a blank the scanner never guessed is never held against it. Nothing here leaves your phone.")
                }

                if ledger.scanCount == 0 {
                    Section {
                        ContentUnavailableView(
                            "No scans yet",
                            systemImage: "chart.bar.doc.horizontal",
                            description: Text("Scan a receipt and confirm it to start measuring accuracy.")
                        )
                    }
                } else {
                    Section("By field") {
                        ForEach(ExtractionField.allCases, id: \.self) { field in
                            fieldRow(field)
                        }
                    }

                    Section {
                        Button("Clear scan data", role: .destructive) {
                            confirmingReset = true
                        }
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmObliterate($confirmingReset) { telemetry.reset() }
        }
    }

    @ViewBuilder
    private func fieldRow(_ field: ExtractionField) -> some View {
        let accuracy = ledger.accuracy(for: field)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(field.displayName)
                Spacer()
                Text(percentText(accuracy))
                    .foregroundStyle(accuracyColor(accuracy))
                    .monospacedDigit()
                    .font(.callout.weight(.medium))
            }
            if let accuracy {
                ProgressView(value: accuracy)
                    .tint(accuracyColor(accuracy))
                Text("\(ledger.corrected(field)) corrected of \(ledger.presented(field)) shown")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                Text("Not yet seen on a scan")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func percentText(_ value: Double?) -> String {
        guard let value else { return "—" }
        return value.formatted(.percent.precision(.fractionLength(0)))
    }

    private func accuracyColor(_ value: Double?) -> Color {
        guard let value else { return .secondary }
        switch value {
        case 0.9...: return .green
        case 0.7..<0.9: return .orange
        default: return .red
        }
    }
}

private extension View {
    /// A destructive confirmation dialog for the reset action.
    func confirmObliterate(_ isPresented: Binding<Bool>, action: @escaping () -> Void) -> some View {
        confirmationDialog("Clear all scan-accuracy data?", isPresented: isPresented, titleVisibility: .visible) {
            Button("Clear", role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This erases the on-device accuracy counts. It can't be undone.")
        }
    }
}
