import SwiftUI
import SwiftData
import VaultCore

/// Settings: the on-device scan-accuracy dashboard and vault export. The
/// accuracy numbers are aggregated locally from every confirmed scan — how
/// often the scanner got each field right before the user touched it — so
/// accuracy improvement is a measured loop, not guesswork.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(StoreManager.self) private var store
    @Query private var purchases: [StoredPurchase]
    // Observed so the dashboard reflects new scans live.
    private var telemetry = ExtractionTelemetryStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var confirmingReset = false
    @State private var confirmingDeleteAllData = false
    /// Flipped once on appear so the accuracy bars animate up from zero.
    @State private var barsFilled = false
    /// Highest XP ever reached. Current XP is derived from the live vault, so
    /// deleting receipts would otherwise *demote* you — being punished for
    /// tidying up is a bad joke. Rank is shown against this high-water mark.
    @AppStorage("rankBestXP") private var bestXP = 0
    /// Last rank the user was actually shown, so a promotion is celebrated
    /// once rather than every time Settings opens.
    @AppStorage("rankLastSeenLevel") private var lastSeenLevel = 1
    @State private var levelUp: VaultRank?
    @State private var exportedFile: ExportedFile?
    @State private var showingPaywall = false
    /// Same key the app root reads, so the choice applies immediately.
    @AppStorage(AppearanceMode.storageKey) private var appearance: AppearanceMode = .system
    /// Pro feature: nudge the user when they're near a store with an open
    /// return window. Off by default — this is an opt-in, not a surprise.
    @AppStorage("proximityRemindersEnabled") private var proximityRemindersEnabled = false
    @AppStorage(OnboardingView.storageKey) private var hasCompletedOnboarding = false
    /// Mirrors the counter VaultView increments on a real scan, so the free
    /// allowance can be exercised without a camera.
    @AppStorage("freeScansUsed") private var freeScansUsed = 0

    private var ledger: AccuracyLedger { telemetry.ledger }

    /// Vault-wide numbers, resolved once in VaultCore via the shared bridge.
    private var insights: InsightsSummary {
        ResolverStore.shared.insights(for: purchases)
    }

    /// Value of purchases still inside an open return window — the paywall pitch.
    private var valueInOpenReturnWindowCents: Int { insights.openReturnValueCents }

    /// Rank measured against the high-water XP, never the momentary vault size.
    private var rank: RankProgress {
        let live = ResolverStore.shared.rankProgress(for: purchases, scansConfirmed: ledger.scanCount)
        return RankLadder.progress(xp: max(live.xp, bestXP))
    }

    /// Records new XP and surfaces a promotion sheet if a rung was crossed.
    private func refreshRank() {
        let live = ResolverStore.shared.rankProgress(for: purchases, scansConfirmed: ledger.scanCount)
        if live.xp > bestXP { bestXP = live.xp }
        let current = RankLadder.progress(xp: bestXP).rank
        guard current.level > lastSeenLevel else {
            // Keep the marker in step if the ladder is ever retuned downward,
            // so an old high level cannot suppress a future promotion.
            lastSeenLevel = min(lastSeenLevel, current.level)
            return
        }
        lastSeenLevel = current.level
        levelUp = current
    }

    var body: some View {
        NavigationStack {
            Form {
                // Debug *and* TestFlight — a TestFlight tester cannot reach Pro
                // until the products are purchasable, so compiling this out of
                // Release removed it from the one build that needed it most.
                // Never present in an App Store build; see BuildEnvironment.
                if BuildEnvironment.allowsDeveloperTools {
                    Section {
                        Toggle("Unlock Pro (dev)", isOn: Binding(
                            get: { store.debugProUnlock },
                            set: { store.debugProUnlock = $0 }))
                        Button("Replay Onboarding") {
                            hasCompletedOnboarding = false
                            dismiss()
                        }
                        // The Simulator has no camera, so the free-scan
                        // allowance is otherwise untestable there. This drives
                        // the same counter the real scan path increments.
                        Stepper(
                            "Free scans used: \(freeScansUsed) / \(ScanAllowance.freeLimit)",
                            value: $freeScansUsed, in: 0...(ScanAllowance.freeLimit + 1)
                        )
                    } header: {
                        Text("Developer")
                    } footer: {
                        Text("Not present in App Store builds. Unlocks camera scan, warranty, export, and widgets so they can be tested before the products are purchasable. Turn it off to test a real sandbox purchase.")
                    }
                }
                Section {
                    RankCard(progress: rank)
                } header: {
                    Text("Rank")
                } footer: {
                    Text("Cosmetic only — ranks never change a deadline or unlock a feature. Every tracked purchase counts, scanned or typed; completed returns count most.")
                }
                appearanceSection
                proximitySection
                if !purchases.isEmpty { insightsSection }
                exportSection
                dataSection
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
            // Pro state swaps whole rows (proximity, export) and the vault
            // emptying swaps entire sections — all hard cuts otherwise. The
            // DEBUG Pro toggle sits directly above these, so the swap is very
            // visible in development.
            .animation(Motion.premium, value: store.isPro)
            .animation(Motion.premium, value: purchases.isEmpty)
            .animation(Motion.premium, value: ledger.scanCount == 0)
            .onAppear {
                barsFilled = true
                refreshRank()
            }
            .fullScreenCover(item: $levelUp) { rank in
                LevelUpView(rank: rank)
            }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .confirmObliterate($confirmingReset) { telemetry.reset() }
            .confirmationDialog(
                "Delete all \(purchases.count) receipts?",
                isPresented: $confirmingDeleteAllData,
                titleVisibility: .visible
            ) {
                Button("Delete Everything", role: .destructive, action: deleteAllData)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This erases every purchase and receipt image on this device (and your private iCloud, if signed in). It can't be undone.")
            }
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
            // These recompute live as purchases are added, returned, or
            // deleted — `.numericText()` rolls the digits instead of swapping
            // them, matching the countdown treatment in PurchaseRow.
            LabeledContent("Tracked purchases") {
                Text("\(s.purchaseCount)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            LabeledContent("Total tracked") {
                Text(Cents(s.totalTrackedCents).formatted(currencyCode: "USD"))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            LabeledContent("In open return windows") {
                Text("\(Cents(s.openReturnValueCents).formatted(currencyCode: "USD")) · \(s.openReturnCount) item\(s.openReturnCount == 1 ? "" : "s")")
                    .foregroundStyle(s.openReturnCount > 0 ? .green : .secondary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            LabeledContent("Warranties active") {
                Text("\(s.activeWarrantyCount)")
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            if s.warrantiesExpiringSoonCount > 0 {
                LabeledContent("Expiring within 30 days") {
                    Text("\(s.warrantiesExpiringSoonCount)")
                        .foregroundStyle(.orange)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
            }
        } header: {
            Text("Insights")
        } footer: {
            Text("Money still recoverable and coverage still in force, across your whole vault.")
        }
        .animation(Motion.snappy, value: s.purchaseCount)
        .animation(Motion.snappy, value: s.openReturnValueCents)

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

    // MARK: Data

    @ViewBuilder
    private var dataSection: some View {
        Section {
            Button("Delete All Receipts", role: .destructive) {
                confirmingDeleteAllData = true
            }
            .disabled(purchases.isEmpty)
        } header: {
            Text("Data")
        } footer: {
            Text("Permanently deletes every purchase in your vault, including scanned receipt images, and cancels their alerts. This can't be undone. To remove just one purchase, swipe it away from the vault list instead.")
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
                // Fill from zero on first appearance, staggered down the list.
                // A bar that is simply *there* at its final length reads as a
                // label; watching it fill is what makes it read as a measure.
                ProgressView(value: barsFilled ? accuracy : 0)
                    .tint(accuracyColor(accuracy))
                    .animation(
                        reduceMotion
                            ? nil
                            : Motion.reveal.delay(Double(fieldIndex(field)) * 0.05),
                        value: barsFilled
                    )
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

    /// Position of a field in the fixed `allCases` order — drives the bar
    /// fill stagger. Falls back to 0 so a new case can never crash the row.
    private func fieldIndex(_ field: ExtractionField) -> Int {
        ExtractionField.allCases.firstIndex(of: field) ?? 0
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

    /// Cancels every purchase's pending alerts, deletes them all from
    /// SwiftData (CloudKit propagates the deletion), then republishes the
    /// widget digest so it reflects the now-empty vault immediately.
    private func deleteAllData() {
        for purchase in purchases {
            let id = purchase.id
            Task { await NotificationScheduler.shared.cancel(purchaseID: id) }
            context.delete(purchase)
        }
        WidgetBridge.publish([], isPro: store.isPro)
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
