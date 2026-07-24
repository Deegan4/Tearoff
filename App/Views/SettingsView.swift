import SwiftUI
import SwiftData
import VaultCore

/// Settings: the on-device scan-accuracy dashboard and vault export. The
/// accuracy numbers are aggregated locally from every confirmed scan — how
/// often the scanner got each field right before the user touched it — so
/// accuracy improvement is a measured loop, not guesswork.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreManager.self) private var store
    @Query private var purchases: [StoredPurchase]
    // Observed so the dashboard reflects new scans live.
    private var telemetry = ExtractionTelemetryStore.shared
    @State private var confirmingReset = false
    @State private var exportedFile: ExportedFile?
    @State private var showingPaywall = false

    private var ledger: AccuracyLedger { telemetry.ledger }

    /// Value of purchases still inside an open return window — the paywall pitch.
    private var valueInOpenReturnWindowCents: Int {
        let today = Date()
        return purchases.reduce(0) { sum, p in
            guard !p.status.isResolved,
                  let w = ResolverStore.shared.returnWindow(for: p),
                  w.deadline >= today else { return sum }
            return sum + p.totalCents.raw
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                exportSection
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
            .sheet(item: $exportedFile) { file in
                ShareSheet(items: [file.url])
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(store: store, valueInWindowCents: valueInOpenReturnWindowCents)
            }
        }
    }

    // MARK: Export (Pro)

    @ViewBuilder
    private var exportSection: some View {
        Section {
            if store.isPro {
                Button {
                    exportedFile = VaultExporter.writeCSV(purchases).map(ExportedFile.init)
                } label: {
                    Label("Export vault (CSV)", systemImage: "square.and.arrow.up")
                }
                .disabled(purchases.isEmpty)
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    HStack {
                        Label("Export vault", systemImage: "square.and.arrow.up")
                        Spacer()
                        Text("Pro")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
            }
        } header: {
            Text("Export")
        } footer: {
            Text(store.isPro
                 ? "Save your whole vault as a CSV — every purchase with its resolved return and warranty deadlines."
                 : "Exporting your vault as a CSV is a Pro feature.")
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
