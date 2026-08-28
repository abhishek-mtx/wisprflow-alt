import AppKit
import SwiftUI

struct MenuBarLabel: View {
    let state: DictationSessionController.State

    var body: some View {
        Image(systemName: iconName)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(.primary)
            .accessibilityLabel("Cadence")
    }

    private var iconName: String {
        switch state {
        case .recording, .handsFree:
            return "waveform"
        case .polishing, .finalizing, .injecting:
            return "waveform"
        case .error:
            return "exclamationmark.triangle"
        case .idle:
            return "mic"
        }
    }
}

struct MenuBarView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            statusHeader
            Divider()
            Button("Open Cadence") {
                openWindow(id: "studio")
                NSApp.activate(ignoringOtherApps: true)
                CadenceWindowSpace.revealStudio()
                DispatchQueue.main.async {
                    CadenceWindowSpace.revealStudio()
                }
            }
            Button(isListening ? "Stop Listening" : "Start Hands-Free Dictation") {
                Task { await appModel.session.toggleHandsFree() }
            }

            Button("Paste Last Transcript") {
                Task { await pasteLast() }
            }
            .disabled(appModel.session.lastInjectedText.isEmpty)

            Divider()
            Button("Settings…") { openSettings() }
                .keyboardShortcut(",", modifiers: .command)

            if !appModel.settings.hasCompletedOnboarding {
                Button("Setup Wizard…") {
                    openWindow(id: "onboarding")
                    CadenceWindowSpace.revealOnboarding()
                    DispatchQueue.main.async {
                        CadenceWindowSpace.revealOnboarding()
                    }
                }
            }

            Divider()
            statsRow
            Divider()
            Button("Quit \(CadenceBrand.name)") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q", modifiers: .command)
        }
        .padding(.vertical, 4)
        .frame(minWidth: 240)
        .onAppear {
            appModel.bootstrapIfNeeded()
        }
    }

    private var isListening: Bool {
        switch appModel.session.state {
        case .recording, .handsFree: true
        default: false
        }
    }

    private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusText)
                .font(.headline)
            Text("Hold \(appModel.settings.pushToTalkShortcut.displayString) to dictate")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusText: String {
        switch appModel.session.state {
        case .idle: return appModel.permissions.microphoneGranted ? "Ready" : "Microphone needed"
        case .recording: return "Listening"
        case .handsFree: return "Listening"
        case .finalizing: return "Finishing…"
        case .polishing: return "Cleaning up…"
        case .injecting: return "Inserting…"
        case .error(let message): return message
        }
    }

    private var statsRow: some View {
        HStack {
            Label("\(StatsStore.shared.todayWords) words today", systemImage: "text.alignleft")
            Spacer()
            Text("Streak \(StatsStore.shared.streak)")
                .foregroundStyle(.secondary)
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func pasteLast() async {
        let text = appModel.session.lastInjectedText
        guard !text.isEmpty else { return }
        appModel.injection.rememberTargetApp()
        _ = await appModel.injection.insert(text, context: appModel.modelContainer.mainContext)
    }
}
