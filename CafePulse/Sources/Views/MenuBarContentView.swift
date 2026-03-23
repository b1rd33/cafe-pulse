import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Status header
            if let session = model.currentSession {
                activeHeader(session)
            } else {
                idleHeader
            }

            Divider().padding(.vertical, 4)

            // Quick dB readout (only when sampling)
            if let sample = model.lastAudioSample {
                dbReadout(sample)
                Divider().padding(.vertical, 4)
            }

            // Actions
            if model.currentSession != nil {
                MenuBarButton(title: "Log Crowd Estimate", icon: "person.3") {
                    model.presentCrowdEstimatePrompt()
                }
                MenuBarButton(title: "End Session", icon: "stop.circle", tint: .red) {
                    model.endSession()
                }
            } else {
                MenuBarButton(title: "Start Session...", icon: "play.circle") {
                    openWindow(id: "main-window")
                    NSApp.activate(ignoringOtherApps: true)
                    model.showStartSessionForm()
                }
            }

            Divider().padding(.vertical, 4)

            MenuBarButton(title: "Open Window", icon: "macwindow") {
                openWindow(id: "main-window")
                NSApp.activate(ignoringOtherApps: true)
            }
            MenuBarButton(title: "Export CSV...", icon: "square.and.arrow.up") {
                model.exportCSV()
            }
            .disabled(model.sessions.isEmpty)

            Divider().padding(.vertical, 4)

            // Sync status
            if model.isAuthenticated {
                syncStatusRow
            }

            MenuBarButton(title: "Quit CafePulse", icon: "xmark.circle") {
                NSApplication.shared.terminate(nil)
            }

            // Status message
            if let msg = model.statusMessage {
                Text(msg)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 260)
    }

    // MARK: - Headers

    private func activeHeader(_ session: Session) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Circle()
                    .fill(.green)
                    .frame(width: 7, height: 7)
                Text(session.cafeName)
                    .font(.system(.body, weight: .medium))
                Spacer()
                Text(model.currentSessionDurationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 12) {
                Label("\(model.currentSessionSampleCount)", systemImage: "waveform")
                Label("\(model.currentSessionCrowdCount)", systemImage: "person.3")
                if model.pendingCrowdPrompt {
                    Label("Due", systemImage: "bell.badge")
                        .foregroundStyle(.orange)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    private var idleHeader: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(.gray.opacity(0.5))
                .frame(width: 7, height: 7)
            Text("Not Recording")
                .font(.system(.body, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 2)
    }

    // MARK: - dB Readout

    private func dbReadout(_ sample: AudioSample) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 0) {
                dbCell(label: "Overall", value: sample.overallDB)
                dbCell(label: "Music", value: sample.musicBandDB, color: .purple)
                dbCell(label: "Voice", value: sample.voiceBandDB, color: .blue)
            }
            HStack(spacing: 8) {
                if sample.selfTalkDetected {
                    Label("You're talking", systemImage: "mic.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                let crowdLevel = crowdLevelText(sample.spectralFlatness)
                Label(crowdLevel, systemImage: "person.3.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
        }
    }

    private func dbCell(label: String, value: Float, color: Color = .primary) -> some View {
        VStack(spacing: 1) {
            Text(String(format: "%.0f", value))
                .font(.system(.title3, design: .rounded, weight: .semibold))
                .foregroundStyle(color)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var syncStatusRow: some View {
        HStack(spacing: 6) {
            switch model.syncManager.syncState {
            case .synced:
                Image(systemName: "checkmark.icloud").foregroundStyle(.green)
                Text("Synced").foregroundStyle(.green)
            case .syncing:
                Image(systemName: "arrow.triangle.2.circlepath.icloud").foregroundStyle(.blue)
                Text("Syncing...").foregroundStyle(.blue)
            case .error(let msg):
                Image(systemName: "exclamationmark.icloud").foregroundStyle(.red)
                Text(msg).foregroundStyle(.red).lineLimit(1)
            case .offline:
                Image(systemName: "icloud.slash").foregroundStyle(.secondary)
                Text("Offline").foregroundStyle(.secondary)
            case .idle:
                Image(systemName: "icloud").foregroundStyle(.secondary)
                Text("Ready").foregroundStyle(.secondary)
            }
        }
        .font(.caption2)
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
    }

    private func crowdLevelText(_ flatness: Float) -> String {
        switch flatness {
        case 0..<0.2: return "Quiet"
        case 0.2..<0.4: return "Some chatter"
        case 0.4..<0.6: return "Moderate crowd"
        case 0.6..<0.8: return "Busy"
        default: return "Very crowded"
        }
    }
}

// MARK: - Menu Bar Button

private struct MenuBarButton: View {
    let title: String
    let icon: String
    var tint: Color = .primary
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .frame(width: 16)
                    .foregroundStyle(tint)
                Text(title)
                    .foregroundStyle(tint)
                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
        }
        .buttonStyle(.plain)
    }
}
