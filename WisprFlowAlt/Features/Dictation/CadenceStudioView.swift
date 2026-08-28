import AppKit
import SwiftUI

struct CadenceStudioView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings
    @State private var pulse = false

    private var isListening: Bool {
        switch appModel.session.state {
        case .recording, .handsFree: true
        default: false
        }
    }

    private var isBusy: Bool {
        switch appModel.session.state {
        case .finalizing, .polishing, .injecting: true
        default: false
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            SiriOrbView(isListening: isListening, isBusy: isBusy, pulse: pulse, size: 80)
                .frame(height: 96)

            Text(statusLine)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Group {
                if isListening || isBusy {
                    Text(appModel.speech.partialTranscript.isEmpty ? "Listening…" : appModel.speech.partialTranscript)
                } else if appModel.session.lastInjectedText.isEmpty {
                    Text("No takes yet")
                } else {
                    Text(appModel.session.lastInjectedText)
                        .lineLimit(4)
                }
            }
            .font(.body)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)

            listenButton

            if !appModel.permissions.microphoneGranted {
                Text(PermissionService.staleMicrophoneHelp)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Allow Microphone") {
                    Task { await appModel.permissions.requestMicrophone() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                if appModel.permissions.microphoneNeedsRelaunch {
                    Button("Relaunch Cadence") {
                        appModel.permissions.relaunchApp()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            Text("Hold \(appModel.settings.pushToTalkShortcut.displayString) to dictate")
                .font(.caption)
                .foregroundStyle(.tertiary)

            if let err = appModel.session.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(20)
        .frame(width: 360, height: 500)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    openSettings()
                } label: {
                    Image(systemName: "gearshape")
                }
                .help("Settings")
            }
        }
        .onAppear {
            CadenceOpeners.openWindow = openWindow
            CadenceOpeners.openSettings = openSettings
            appModel.bootstrapIfNeeded()
            NSApp.activate()
            CadenceWindowSpace.pinVisibleChrome()
            appModel.permissions.refresh()
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) {
                pulse = true
            }
            Task { @MainActor in
                if appModel.permissions.microphoneStatus == .notDetermined {
                    await appModel.permissions.requestMicrophone()
                }
                appModel.speech.armAudioIfNeeded()
                appModel.applyHotkeySettings()
                if !appModel.hotkeys.isRunning {
                    appModel.hotkeys.start()
                }
                appModel.permissions.refresh()
                CadenceLog.debug(
                    "Studio appear hotkeysRunning=\(appModel.hotkeys.isRunning) mic=\(appModel.permissions.microphoneGranted) ax=\(appModel.permissions.accessibilityTrusted) input=\(appModel.permissions.inputMonitoringTrusted)"
                )
            }
        }
        .onChange(of: appModel.permissions.microphoneGranted) { _, granted in
            guard granted else { return }
            appModel.session.clearPermissionError()
        }
    }

    private var listenButton: some View {
        Button {
            if !appModel.permissions.microphoneGranted {
                if appModel.permissions.microphoneNeedsRelaunch {
                    appModel.permissions.relaunchApp()
                } else {
                    Task { await appModel.permissions.requestMicrophone() }
                }
                return
            }
            Task { await appModel.session.toggleHandsFree() }
        } label: {
            Image(systemName: isListening ? "stop.fill" : "mic.fill")
                .font(.title2.weight(.semibold))
                .frame(width: 56, height: 56)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
        .tint(isListening ? .red : .accentColor)
        .accessibilityLabel(isListening ? "Stop" : "Listen")
        .help(isListening ? "Stop" : "Listen")
    }

    private var statusLine: String {
        switch appModel.session.state {
        case .idle: return appModel.permissions.microphoneGranted ? "Ready" : "Microphone needed"
        case .recording, .handsFree: return "Listening…"
        case .finalizing: return "Finishing…"
        case .polishing: return "Cleaning up…"
        case .injecting: return "Inserting text…"
        case .error: return "Something went wrong"
        }
    }
}

/// Compact Siri-like orb: overlapping translucent discs, no page gradient.
struct SiriOrbView: View {
    var isListening: Bool
    var isBusy: Bool = false
    var pulse: Bool = false
    var size: CGFloat = 88

    var body: some View {
        ZStack {
            Circle()
                .fill(Color.blue.opacity(isListening ? 0.22 : 0.10))
                .frame(width: size * 1.18, height: size * 1.18)
                .blur(radius: 12)
                .scaleEffect(isListening && pulse ? 1.08 : 1.0)

            ZStack {
                Circle()
                    .fill(Color(red: 0.20, green: 0.52, blue: 0.98).opacity(0.92))
                    .frame(width: size * 0.78, height: size * 0.72)
                    .offset(y: size * 0.08)

                Circle()
                    .fill(Color(red: 0.48, green: 0.32, blue: 0.95).opacity(0.82))
                    .frame(width: size * 0.62, height: size * 0.58)
                    .offset(x: -size * 0.12, y: -size * 0.06)

                Circle()
                    .fill(Color(red: 0.95, green: 0.42, blue: 0.72).opacity(0.70))
                    .frame(width: size * 0.50, height: size * 0.46)
                    .offset(x: size * 0.14, y: -size * 0.10)

                Circle()
                    .fill(.white.opacity(0.55))
                    .frame(width: size * 0.22, height: size * 0.18)
                    .offset(x: -size * 0.10, y: -size * 0.16)
                    .blur(radius: 1.5)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay {
                Circle().strokeBorder(.white.opacity(0.28), lineWidth: 0.8)
            }
            .shadow(color: .black.opacity(0.12), radius: 8, y: 3)
        }
        .frame(width: size * 1.2, height: size * 1.2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(isListening ? "Listening" : (isBusy ? "Processing" : "Cadence"))
    }
}
