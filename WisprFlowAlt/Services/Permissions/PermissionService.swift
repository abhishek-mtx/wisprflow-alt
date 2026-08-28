import AVFoundation
import AppKit
import ApplicationServices
import Foundation
import Observation

@MainActor
@Observable
final class PermissionService {
    var microphoneGranted = false
    var microphoneStatus: AVAuthorizationStatus = .notDetermined
    var speechRecognitionGranted = false
    var accessibilityTrusted = false
    var inputMonitoringTrusted = false
    /// Settings can show Cadence ON while this binary’s code signature no longer matches TCC.
    var accessibilityLooksStale = false
    var lastTrustNote: String?

    var allRequiredGranted: Bool {
        microphoneGranted && inputMonitoringTrusted
    }

    /// macOS often keeps `.denied` on the live process after the user flips the Settings switch.
    var microphoneNeedsRelaunch: Bool {
        microphoneStatus == .denied || microphoneStatus == .restricted
    }

    private var pollTask: Task<Void, Never>?
    private var activationTask: Task<Void, Never>?

    func observeAppActivation() {
        guard activationTask == nil else { return }
        activationTask = Task { [weak self] in
            let notes = NotificationCenter.default.notifications(named: NSApplication.didBecomeActiveNotification)
            for await _ in notes {
                guard !Task.isCancelled else { return }
                self?.refresh()
            }
        }
    }

    func refresh() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        let mic = status == .authorized
        let ax = AXIsProcessTrusted()
        let input = CGPreflightListenEventAccess()
        let axStale = !ax

        let changed = microphoneGranted != mic
            || microphoneStatus != status
            || accessibilityTrusted != ax
            || inputMonitoringTrusted != input
            || speechRecognitionGranted != mic
            || accessibilityLooksStale != axStale

        microphoneGranted = mic
        microphoneStatus = status
        accessibilityTrusted = ax
        inputMonitoringTrusted = input
        speechRecognitionGranted = mic
        accessibilityLooksStale = axStale

        if changed {
            CadenceLog.info(
                "Permissions changed mic=\(mic) tcc=\(Self.label(for: status)) ax=\(ax) input=\(input)"
            )
        }
    }

    func requestMicrophone() async {
        lastTrustNote = Self.staleMicrophoneHelp
        let status = AVCaptureDevice.authorizationStatus(for: .audio)
        switch status {
        case .authorized:
            microphoneGranted = true
            microphoneStatus = status
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneGranted = granted
            microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            if !granted {
                openSystemSettings(pane: "Privacy_Microphone")
            }
        default:
            microphoneGranted = false
            microphoneStatus = status
            openSystemSettings(pane: "Privacy_Microphone")
        }
        refresh()
        if !microphoneGranted {
            startPolling()
        }
    }

    /// Opens Accessibility settings without prompting. Use when the Cadence row is already ON.
    func openAccessibilitySettings() {
        lastTrustNote = Self.staleAccessibilityHelp
        openSystemSettings(pane: "Privacy_Accessibility")
        startPolling()
    }

    /// Binds Accessibility to *this* running binary. Settings can stay ON for an old Cadence copy.
    func grantAccessibilityForThisBuild() {
        lastTrustNote = Self.staleAccessibilityHelp
        // Never tccutil-reset here: it deletes the grant the user just gave. Builds are
        // signed with a stable identity now, so a grant carries across rebuilds.
        openSystemSettings(pane: "Privacy_Accessibility")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
            self.accessibilityTrusted = AXIsProcessTrustedWithOptions(options)
            self.refresh()
        }
        startPolling()
    }

    func requestAccessibility() {
        grantAccessibilityForThisBuild()
    }

    func requestInputMonitoring() {
        lastTrustNote = Self.staleInputMonitoringHelp
        // Do not tccutil-reset here — that clears the grant and breaks Fn until re-enabled.
        openSystemSettings(pane: "Privacy_ListenEvent")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            let granted = CGRequestListenEventAccess()
            self.inputMonitoringTrusted = granted || CGPreflightListenEventAccess()
            self.refresh()
        }
        startPolling()
    }

    func openSystemSettings(pane: String) {
        let urlString = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }

    /// Quit and reopen so TCC re-reads Microphone for this process.
    func relaunchApp() {
        CadenceLog.info("Relaunching Cadence so microphone TCC is re-read")
        let path = Bundle.main.bundlePath
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", "sleep 0.4; /usr/bin/open '\(path)'"]
        do {
            try process.run()
        } catch {
            CadenceLog.error("Relaunch failed: \(error.localizedDescription)")
            return
        }
        NSApplication.shared.terminate(nil)
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { @MainActor in
            for _ in 0..<40 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                refresh()
                if allRequiredGranted { return }
            }
        }
    }

    private static func label(for status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .restricted: return "restricted"
        case .notDetermined: return "notDetermined"
        @unknown default: return "unknown(\(status.rawValue))"
        }
    }

    static let staleMicrophoneHelp = """
    Allow Microphone for Cadence. If the switch is already ON, quit Cadence completely and reopen it so this process re-reads TCC.
    """

    static let staleAccessibilityHelp = """
    If Cadence is already ON in Settings, macOS is approving an older copy. Select Cadence, click − to remove the row, then drag /Applications/Cadence.app back in and switch it ON.
    """

    static let staleInputMonitoringHelp = """
    If Cadence is already ON under Input Monitoring, remove that row and add /Applications/Cadence.app again. Fn push-to-talk stays dead until this grant is bound to the running copy.
    """
}
