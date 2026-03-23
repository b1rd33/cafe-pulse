import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                if model.currentSession == nil {
                    idleSection
                } else {
                    activeSessionSection
                }

                if !model.sessions.isEmpty {
                    sessionHistorySection
                }

                settingsSection
            }
            .padding(24)
        }
        .frame(minWidth: 480, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Export CSV") {
                    model.exportCSV()
                }
                .disabled(model.sessions.isEmpty)
            }
        }
        .onAppear { model.isMainWindowVisible = true }
        .onDisappear { model.isMainWindowVisible = false }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("CafePulse")
                    .font(.largeTitle.weight(.bold))
                Text(model.isSampling
                     ? "Sampling every \(Int(model.settings.sampleIntervalSeconds))s"
                     : "Ready to start")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            statusBadge
        }
    }

    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(model.isSampling ? .green : .gray)
                .frame(width: 10, height: 10)
            Text(model.isSampling ? "Recording" : "Idle")
                .font(.callout.weight(.medium))
                .foregroundStyle(model.isSampling ? .green : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill((model.isSampling ? Color.green : Color.gray).opacity(0.15))
        )
    }

    // MARK: - Idle

    private var idleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.isStartSessionFormVisible {
                StartSessionFormView(
                    draft: Binding(
                        get: { model.startSessionDraft },
                        set: { model.startSessionDraft = $0 }
                    ),
                    suggestions: model.previousCafeSuggestions,
                    onStart: model.startSession,
                    onCancel: model.cancelStartSession
                )
            } else {
                Button("Start Session") {
                    model.showStartSessionForm()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
        }
    }

    // MARK: - Active Session

    private var activeSessionSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Session info
            VStack(alignment: .leading, spacing: 4) {
                Text(model.currentSession?.cafeName ?? "Active Session")
                    .font(.title2.weight(.semibold))
                if let location = model.currentSession?.location, !location.isEmpty {
                    Text(location)
                        .foregroundStyle(.secondary)
                }
            }

            // Stats grid
            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: 12) {
                WindowStatCard(title: "Duration", value: model.currentSessionDurationText, icon: "clock")
                WindowStatCard(title: "Samples", value: "\(model.currentSessionSampleCount)", icon: "waveform")
                WindowStatCard(title: "Crowd Logs", value: "\(model.currentSessionCrowdCount)", icon: "person.3")
            }

            // Live dB readings
            if let sample = model.lastAudioSample {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Live Audio Levels")
                            .font(.headline)
                        Spacer()
                        if sample.selfTalkDetected {
                            Label("You're talking", systemImage: "mic.fill")
                                .font(.caption)
                                .foregroundStyle(.orange)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Capsule().fill(.orange.opacity(0.15)))
                        }
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        WindowStatCard(title: "Overall", value: dbString(sample.overallDB), icon: "speaker.wave.3")
                        WindowStatCard(title: "Music (bass)", value: dbString(sample.musicBandDB), icon: "music.note")
                        WindowStatCard(title: "Voice (mid)", value: dbString(sample.voiceBandDB), icon: "person.wave.2")
                    }

                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        WindowStatCard(
                            title: "Crowd (auto)",
                            value: crowdLevelText(sample.spectralFlatness),
                            icon: "person.3.fill"
                        )
                        WindowStatCard(
                            title: "Flatness",
                            value: String(format: "%.2f", sample.spectralFlatness),
                            icon: "chart.bar"
                        )
                        WindowStatCard(title: "Peak", value: dbString(sample.peakDB), icon: "speaker.wave.3.fill")
                    }
                }
            }

            // Actions
            HStack(spacing: 12) {
                Button("Log Crowd Estimate") {
                    model.presentCrowdEstimatePrompt()
                }
                .controlSize(.large)

                Spacer()

                Button("End Session", role: .destructive) {
                    model.endSession()
                }
                .controlSize(.large)
            }
        }
    }

    // MARK: - Session History

    private var sessionHistorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Previous Sessions")
                .font(.headline)

            ForEach(model.sessions.filter { !$0.isActive }.suffix(10).reversed()) { session in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(session.cafeName)
                            .font(.body.weight(.medium))
                        Text(session.startedAt, style: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let endedAt = session.endedAt {
                        Text(Self.durationFormatter.string(from: session.startedAt, to: endedAt) ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            }
        }
    }

    // MARK: - Settings

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Settings")
                .font(.headline)

            Stepper(
                value: Binding(
                    get: { model.settings.sampleIntervalSeconds },
                    set: { model.updateSampleInterval($0) }
                ),
                in: 5...60, step: 5
            ) {
                Text("Sample interval: \(Int(model.settings.sampleIntervalSeconds)) seconds")
            }

            Stepper(
                value: Binding(
                    get: { model.settings.crowdPromptIntervalSeconds / 60 },
                    set: { model.updateCrowdPromptInterval(minutes: $0) }
                ),
                in: 5...60, step: 5
            ) {
                Text("Crowd prompt interval: \(Int(model.settings.crowdPromptIntervalSeconds / 60)) minutes")
            }
        }
    }

    // MARK: - Helpers

    private func dbString(_ value: Float) -> String {
        String(format: "%.1f dB", value)
    }

    private func crowdLevelText(_ flatness: Float) -> String {
        switch flatness {
        case 0..<0.2: return "Quiet"
        case 0.2..<0.4: return "Some chatter"
        case 0.4..<0.6: return "Moderate"
        case 0.6..<0.8: return "Busy"
        default: return "Very crowded"
        }
    }

    private static let durationFormatter: DateComponentsFormatter = {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = [.hour, .minute]
        formatter.unitsStyle = .abbreviated
        formatter.maximumUnitCount = 2
        return formatter
    }()
}

// MARK: - Window Stat Card

private struct WindowStatCard: View {
    let title: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor))
        )
    }
}
