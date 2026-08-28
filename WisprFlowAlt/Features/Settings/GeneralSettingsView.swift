import SwiftUI

struct GeneralSettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var settings = appModel.settings
        Form {
            Section("Transcription") {
                Toggle("Polish with Apple Intelligence", isOn: $settings.polishEnabled)
                Toggle("Inject polished text (keep raw in history)", isOn: $settings.injectPolishedOnly)
                Toggle("Show floating HUD while dictating", isOn: $settings.showHUD)
                TextField("Locale identifier", text: $settings.preferredLocaleIdentifier)
                LabeledContent("Foundation Models") {
                    Text(appModel.polish.isAvailable ? "Available" : "Unavailable")
                        .foregroundStyle(appModel.polish.isAvailable ? .green : .secondary)
                }
            }

            Section("Permissions") {
                permissionRow("Microphone", appModel.permissions.microphoneGranted) {
                    Task { await appModel.permissions.requestMicrophone() }
                }
                permissionRow(
                    "Accessibility",
                    appModel.permissions.accessibilityTrusted,
                    detail: appModel.permissions.accessibilityTrusted
                        ? nil
                        : PermissionService.staleAccessibilityHelp
                ) {
                    appModel.permissions.grantAccessibilityForThisBuild()
                }
                permissionRow(
                    "Input Monitoring",
                    appModel.permissions.inputMonitoringTrusted,
                    detail: appModel.permissions.inputMonitoringTrusted
                        ? nil
                        : PermissionService.staleInputMonitoringHelp
                ) {
                    appModel.permissions.requestInputMonitoring()
                    appModel.hotkeys.stop()
                    appModel.hotkeys.start()
                }
                Button("Refresh permissions") {
                    appModel.permissions.refresh()
                }
                if appModel.permissions.microphoneNeedsRelaunch {
                    Text(PermissionService.staleMicrophoneHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Relaunch Cadence") {
                        appModel.permissions.relaunchApp()
                    }
                }
                if let note = appModel.permissions.lastTrustNote, !appModel.permissions.accessibilityTrusted {
                    Text(note)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("About") {
                LabeledContent("Version", value: "1.0.0")
                Text("\(CadenceBrand.name) — on-device speech-to-text for macOS 26+. No cloud STT.")
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
        .onAppear {
            appModel.permissions.refresh()
        }
    }

    private func permissionRow(
        _ title: String,
        _ granted: Bool,
        detail: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Image(systemName: granted ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(granted ? .green : .orange)
                if !granted {
                    #if DEBUG
                    Button("Grant this build", action: action)
                    #else
                    Button("Enable", action: action)
                    #endif
                }
            }
            if let detail, !granted {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
