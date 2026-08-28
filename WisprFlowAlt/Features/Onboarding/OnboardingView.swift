import AppKit
import SwiftUI

struct OnboardingView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openWindow) private var openWindow
    @State private var step = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }
        .background(.background)
        .onAppear { appModel.permissions.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(CadenceBrand.name)
                .font(.largeTitle.weight(.semibold))
            Text("Welcome")
                .font(.title2.weight(.semibold))
            Text("\(CadenceBrand.tagline). Speech stays on this Mac.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case 0:
            permissionCard(
                title: "Microphone",
                detail: "Required to capture speech for on-device transcription.",
                granted: appModel.permissions.microphoneGranted,
                actionTitle: "Allow Microphone"
            ) {
                Task { await appModel.permissions.requestMicrophone() }
            }
        case 1:
            permissionCard(
                title: "Accessibility",
                detail: "Needed to paste into the app you’re typing in. If Cadence is already ON in Settings, remove that row first — macOS is still bound to an older build.",
                granted: appModel.permissions.accessibilityTrusted,
                actionTitle: "Enable Accessibility"
            ) {
                appModel.permissions.requestAccessibility()
            }
        case 2:
            permissionCard(
                title: "Input Monitoring",
                detail: "Required for global push-to-talk and command-mode hotkeys.",
                granted: appModel.permissions.inputMonitoringTrusted,
                actionTitle: "Enable Input Monitoring"
            ) {
                appModel.permissions.requestInputMonitoring()
            }
        default:
            VStack(alignment: .leading, spacing: 12) {
                Text("You're ready")
                    .font(.title3.weight(.semibold))
                Text("Hold \(appModel.settings.pushToTalkShortcut.displayString) to dictate. Hands-free double-tap is optional and off by default. Turn it on in Settings → Hotkeys. Use \(appModel.settings.commandModeShortcut.displayString) for Command Mode.")
                    .foregroundStyle(.secondary)
                Text("Add names and jargon in Settings → Dictionary so they always spell the way you want.")
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
    }

    private func permissionCard(
        title: String,
        detail: String,
        granted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.title3.weight(.semibold))
                Spacer()
                Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(granted ? .green : .secondary)
            }
            Text(detail)
                .foregroundStyle(.secondary)
            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .disabled(granted)
                .accessibilityLabel(actionTitle)
            Button("Refresh status") {
                appModel.permissions.refresh()
            }
            .buttonStyle(.link)
            .accessibilityLabel("Refresh status")
        }
        .padding(24)
    }

    private var footer: some View {
        HStack {
            if step > 0 {
                Button("Back") { step -= 1 }
                    .accessibilityLabel("Back")
            }
            Spacer()
            if step < 3 {
                Button(step < 2 || appModel.permissions.allRequiredGranted ? "Continue" : "Skip for now") {
                    step += 1
                    appModel.permissions.refresh()
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel(step < 2 || appModel.permissions.allRequiredGranted ? "Continue" : "Skip for now")
            } else {
                Button("Finish") {
                    appModel.settings.hasCompletedOnboarding = true
                    appModel.hotkeys.start()
                    dismiss()
                    NSApp.windows.first { $0.identifier?.rawValue == "onboarding" }?.close()
                    openWindow(id: "studio")
                    CadenceWindowSpace.revealStudio()
                    DispatchQueue.main.async {
                        CadenceWindowSpace.revealStudio()
                    }
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Finish")
            }
        }
        .padding(16)
    }
}
