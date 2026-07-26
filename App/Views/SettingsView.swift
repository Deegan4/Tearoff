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
    /// Same key the app root reads, so the choice applies immediately.
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system
    /// Pro feature: nudge the user when they're near a store with an open
    /// return window. Off by default — this is an opt-in, not a surprise.
    @AppStorage("proximityRemindersEnabled") private var proximityRemindersEnabled = false

    private var ledger: AccuracyLedger { telemetry.ledger }

    /// Vault-wide numbers, resolved once in VaultCore via the shared bridge.
    private var insights: InsightsSummary {
        ResolverStore.shared.insights(for: purchases)
    }

    /// Value of purchases still inside an open return window — the paywall pitch.
    private var valueInOpenReturnWindowCents: Int { insights.openReturnValueCents }

    var body: some View {
        NavigationStack {
            Form {
                #if DEBUG
                Section {
                    Toggle("Unlock Pro (dev)", isOn: Binding(
                        get: { store.debugProUnlock },
                        set: { store.debugProUnlock = $0 }))
                } header: {
                    Text("Developer")
                } footer: {
                    Text("Dev builds have no purchasable products; this unlocks camera scan, warranty, export, and widgets for testing.")
                }
                #endif
                appearanceSection
                proximitySection
                if !purchases.isEmpty { insightsSection }
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

    // MARK: Appearance

    @ViewBuilder
    private var appearanceSection: some View {
        Section {
            Picker("Appearance", selection: $appearance) {
                ForEach(AppearanceMode.allCases) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Appearance")
        } footer: {
            Text("System follows your device's Light/Dark setting.")
        }
    }

    // MARK: Insights

    @ViewBuilder
    private var insightsSection: some View {
        let s = insights
        Section {
            LabeledContent("Tracked purchases", value: "\(s.purchaseCount)")
            LabeledContent("Total tracked", value: Cents(s.totalTrackedCents).formatted(currencyCode: "USD"))
            LabeledContent("In open return windows") {
                Text("\(Cents(s.openReturnValueCents).formatted(currencyCode: "USD")) · \(s.openReturnCount) item\(s.openReturnCount == 1 ? "" : "s")")
                    .foregroundStyle(s.openReturnCount > 0 ? .green : .secondary)
                    .monospacedDigit()
            }
            LabeledContent("Warranties active", value: "\(s.activeWarrantyCount)")
            if s.warrantiesExpiringSoonCount > 0 {
                LabeledContent("Expiring within 30 days") {
                    Text("\(s.warrantiesExpiringSoonCount)").foregroundStyle(.orange)
                }
            }
        } header: {
            Text("Insights")
        } footer: {
            Text("Money still recoverable and coverage still in force, across your whole vault.")
        }

        if !s.topCategories.isEmpty {
            Section("Spending by category") {
                ForEach(s.topCategories) { c in
                    HStack {
                        Text(c.category)
                        Spacer(minLength: 12)
                        Text(Cents(c.totalCents).formatted(currencyCode: "USD"))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text("· \(c.count)")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
    }

    // MARK: Proximity reminders (Pro)

    @ViewBuilder
    private var proximitySection: some View {
        Section {
            if store.isPro {
                Toggle("Remind me near a store", isOn: Binding(
                    get: { proximityRemindersEnabled },
                    set: { on in
                        proximityRemindersEnabled = on
                        if on { ProximityReminder.shared.requestAuthorization() }
                    }))
            } else {
                Button { showingPaywall = true } label: {
                    HStack {
                        Text("Remind me near a store")
                        Spacer()
                        Text("Pro")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.tint.opacity(0.15), in: Capsule())
                    }
                }
            }
        } header: {
            Text("Proximity")
        } footer: {
            Text(store.isPro
                 ? "A quick nudge when you're near a store with an open return window. Your location is checked only while the app is open and is never stored or sent anywhere."
                 : "Get a nudge when you're near a store with an open return window — Pro feature.")
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
                Button {
                    exportedFile = VaultExporter.writePDFReport(purchases).map(ExportedFile.init)
                } label: {
                    Label("Year in Review (PDF)", systemImage: "doc.richtext")
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
