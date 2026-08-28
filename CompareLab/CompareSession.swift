import AppKit
import AVFoundation
import Foundation
import Observation

@MainActor
@Observable
final class CompareSession {
    var isRecording = false
    var isBusy = false
    var lastError: String?
    var cadence = EngineResult.blank(name: "Cadence", subtitle: "macOS 26 Speech Transcriber")
    var parakeet = EngineResult.blank(name: "Parakeet", subtitle: "TDT 0.6b · MLX · Hugging Face")
    var wispr = EngineResult.blank(name: "Wispr Flow", subtitle: "Cloud API")
    var parakeetLoadMs: Int?
    var wisprKeyDraft = WisprEngine.apiKey
    var wisprPasteDraft = ""
    var fnArmed = false
    var fnHint = "Hold Fn — Cadence, Parakeet, and Wispr Flow all listen"

    private let recorder = ClipRecorder()
    private let parakeetEngine = ParakeetEngine()
    private var parakeetWarmTask: Task<Void, Never>?
    private let fnMonitor = FnHoldMonitor()
    private var pendingCadenceText: String?
    private var clipboardBefore = ""
    private var didBootstrap = false

    var hasWisprAPIKey: Bool { WisprEngine.hasAPIKey }
    var parakeetLoading: Bool { parakeetWarmTask != nil && parakeetLoadMs == nil && parakeet.status != .failed }

    func bootstrap() {
        if didBootstrap { return }
        didBootstrap = true
        wispr.subtitle = WisprEngine.desktopInstalled
            ? "Desktop installed · set Wispr hotkey to Fn"
            : "Cloud API (key required)"
        if WisprEngine.hasAPIKey {
            wispr.status = .idle
            wispr.error = nil
        }
        parakeetWarmTask = Task { await warmParakeetInBackground() }
        armFn()
        DistributedNotificationCenter.default().addObserver(
            forName: CompareSync.cadenceTranscript,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let text = (note.userInfo?[CompareSync.transcriptKey] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            Task { @MainActor in
                if let text, !text.isEmpty {
                    self?.pendingCadenceText = text
                }
            }
        }
        if WisprEngine.desktopInstalled {
            WisprEngine.openDesktopApp(activates: false)
        }
        if CompareSync.cadenceIsRunning() == false {
            let url = URL(fileURLWithPath: "/Applications/Cadence.app")
            let config = NSWorkspace.OpenConfiguration()
            config.activates = false
            NSWorkspace.shared.openApplication(at: url, configuration: config)
        }
    }

    func saveWisprKey() {
        WisprEngine.apiKey = wisprKeyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        wispr.subtitle = WisprEngine.hasAPIKey ? "Cloud API · REST" : wispr.subtitle
        if WisprEngine.hasAPIKey {
            wispr.status = .idle
            wispr.error = nil
        }
    }

    func applyWisprPaste() {
        let text = wisprPasteDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        wispr.status = .done
        wispr.transcript = text
        wispr.error = nil
        wispr.inferMs = nil
        wispr.loadMs = nil
        wispr.subtitle = "Desktop Wispr Flow (manual paste)"
        wisprPasteDraft = ""
    }

    func toggleRecord() async {
        if isRecording {
            await stopAndTranscribe()
            return
        }
        await startHold()
    }

    private func armFn() {
        fnMonitor.onBegan = { [weak self] in
            Task { @MainActor in
                guard let self, !self.isRecording, !self.isBusy else { return }
                await self.startHold()
            }
        }
        fnMonitor.onEnded = { [weak self] in
            Task { @MainActor in
                guard let self, self.isRecording else { return }
                await self.stopAndTranscribe()
            }
        }
        fnMonitor.start()
        fnArmed = fnMonitor.isRunning
        if let err = fnMonitor.lastError {
            lastError = err
        }
    }

    private func startHold() async {
        lastError = nil
        let granted = await recorder.requestPermission()
        guard granted else {
            lastError = "Allow Microphone for Compare in System Settings."
            return
        }
        do {
            clipboardBefore = NSPasteboard.general.string(forType: .string) ?? ""
            pendingCadenceText = nil
            try recorder.start()
            isRecording = true
            CompareSync.postBegan()
            cadence.status = .running
            parakeet.status = .idle
            wispr.status = .running
            cadence.transcript = ""
            parakeet.transcript = ""
            wispr.transcript = ""
            cadence.error = nil
            parakeet.error = nil
            wispr.error = nil
            cadence.subtitle = CompareSync.cadenceIsRunning()
                ? "Live Cadence (Fn)"
                : "macOS 26 Speech Transcriber"
            wispr.subtitle = WisprEngine.desktopInstalled
                ? "Listening via Wispr Fn…"
                : wispr.subtitle
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func warmParakeetInBackground() async {
        do {
            try await parakeetEngine.warmup()
            parakeetLoadMs = await parakeetEngine.loadMs
            parakeet.loadMs = parakeetLoadMs
            if parakeet.status != .running && parakeet.status != .done {
                parakeet.status = .idle
            }
        } catch {
            parakeet.status = .failed
            parakeet.error = error.localizedDescription
        }
        parakeetWarmTask = nil
    }

    private func stopAndTranscribe() async {
        isRecording = false
        guard let url = recorder.stop() else {
            lastError = "No recording captured"
            CompareSync.postEnded()
            return
        }
        isBusy = true
        parakeet.status = .running

        async let parakeetRun = parakeetEngine.transcribe(fileURL: url)
        async let cadenceLive = waitForCadenceTranscript()
        async let wisprClip = waitForWisprClipboard()

        let live = await cadenceLive
        if let live, !live.isEmpty {
            cadence.status = .done
            cadence.transcript = live
            cadence.subtitle = "Live Cadence (Fn)"
            cadence.error = nil
        } else {
            cadence.status = .running
            cadence = await AppleEngine.transcribe(fileURL: url)
        }
        parakeet = await parakeetRun

        if WisprEngine.hasAPIKey {
            wispr = await WisprEngine.transcribe(fileURL: url)
        } else if let clip = await wisprClip, !clip.isEmpty {
            wispr.status = .done
            wispr.transcript = clip
            wispr.subtitle = "Wispr Flow desktop (clipboard)"
            wispr.error = nil
        } else if wispr.transcript.isEmpty {
            wispr.status = .failed
            wispr.error = WisprEngine.desktopInstalled
                ? "Set Wispr Flow’s hotkey to Fn, then hold Fn again. Or paste the Wispr transcript."
                : "No API key. Add one, or paste from Wispr Flow."
        }
        isBusy = false
        CompareSync.postEnded()
    }

    private func waitForCadenceTranscript() async -> String? {
        let deadline = Date().addingTimeInterval(12)
        while Date() < deadline {
            if let text = pendingCadenceText, !text.isEmpty { return text }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return pendingCadenceText
    }

    private func waitForWisprClipboard() async -> String? {
        let deadline = Date().addingTimeInterval(4)
        while Date() < deadline {
            let now = NSPasteboard.general.string(forType: .string) ?? ""
            let trimmed = now.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != clipboardBefore {
                return trimmed
            }
            try? await Task.sleep(nanoseconds: 80_000_000)
        }
        return nil
    }
}
